//+------------------------------------------------------------------+
//| logging.mqh - GrowBuddy logging (MySQL backend, no INI)         |
//| Uses MQLMySQL interface (MQLMySQL.dll + libmysql.dll)            |
//+------------------------------------------------------------------+
#property strict

#include <MQLMySQL.mqh> // require MQLMySQL.dll + libmysql.dll deployed in MQL5\Libraries

// Default MySQL connection parameters (you provided these)
static string LOG_DB_HOST     = "127.0.0.1";
static string LOG_DB_USER     = "root";
static string LOG_DB_PASSWORD = "root";
static string LOG_DB_DATABASE = "growbuddy";
static int    LOG_DB_PORT     = 3306;
static string LOG_DB_SOCKET   = "";   // not used for TCP
static int    LOG_DB_CLIENTFLAG = 0;  // default client flags

#define LOG_BUFFER_MAX       4096
#define LOG_FLUSH_RETRY_MS   50
#define LOG_FLUSH_RETRIES    5

// ---------------- internal state ----------------
static int     LOG_db_handle = 0;               // MySQL connection id
static string  LOG_db_conninfo = "";            // printable conn info
static bool    LOG_db_ready = false;
static bool    LOG_debug_enabled = false;
static bool    LOG_wrapper_initialized = false;
static bool    LOG_buffer_enabled = true;

// ring buffer
static string  LOG_buffer[LOG_BUFFER_MAX];
static int     LOG_buffer_head = 0;
static int     LOG_buffer_tail = 0;
static int     LOG_buffer_count = 0;

// auto-flush
static bool    LOG_auto_flush_enabled = false;
static int     LOG_auto_flush_interval = 0;

// ---------------- schema (MySQL dialect) ----------------
static string LOG_RUNS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS runs ("
" run_key VARCHAR(255) NOT NULL PRIMARY KEY,"
" name TEXT,"
" started_at DATETIME,"
" finished_at DATETIME,"
" config_json JSON"
") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";

static string LOG_SIGNALS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS signals ("
" id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,"
" run_key VARCHAR(255) NOT NULL,"
" decision_id VARCHAR(255) NOT NULL,"
" ts_utc DATETIME NOT NULL,"
" tf_iTime INT,"
" symbol VARCHAR(64),"
" timeframe VARCHAR(32),"
" tenkan DOUBLE,"
" kijun DOUBLE,"
" senkouA DOUBLE,"
" senkouB DOUBLE,"
" chikou DOUBLE,"
" signal TINYINT,"
" reason_json JSON,"
" blocked_json JSON,"
" extra_json JSON,"
" INDEX (run_key), INDEX (decision_id), INDEX (ts_utc)"
") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";

static string LOG_PLANS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS plans ("
" id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,"
" run_key VARCHAR(255) NOT NULL,"
" decision_id VARCHAR(255) NOT NULL,"
" plan_id VARCHAR(255) NOT NULL,"
" ts_utc DATETIME NOT NULL,"
" planned_type VARCHAR(64),"
" side VARCHAR(16),"
" volume DOUBLE,"
" price DOUBLE,"
" sl DOUBLE,"
" tp DOUBLE,"
" comment TEXT,"
" effective_params_json JSON,"
" extra_json JSON,"
" INDEX (run_key), INDEX (decision_id), INDEX (plan_id), INDEX (ts_utc)"
") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";

static string LOG_EXECUTIONS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS executions ("
" id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,"
" run_key VARCHAR(255) NOT NULL,"
" plan_id VARCHAR(255) NOT NULL,"
" ts_utc DATETIME NOT NULL,"
" request_json JSON,"
" result_json JSON,"
" retcode INT,"
" retcode_desc VARCHAR(255),"
" order_ticket BIGINT,"
" filled_price DOUBLE,"
" assigned_sl DOUBLE,"
" assigned_tp DOUBLE,"
" INDEX (run_key), INDEX (plan_id), INDEX (ts_utc)"
") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";

// ---------------- utilities ----------------
string LOG_SQL_Escape(const string s)
{
   if(StringLen(s) == 0) return "";
   string out = s;
   // escape backslash then single quote for MySQL string literal
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "'", "\\'");
   return out;
}

bool LOG_BufferPush(const string sql)
{
   if(!LOG_buffer_enabled) return false;
   if(LOG_buffer_count >= LOG_BUFFER_MAX)
   {
      // drop oldest to make room
      LOG_buffer_head = (LOG_buffer_head + 1) % LOG_BUFFER_MAX;
      LOG_buffer_count--;
      if(LOG_debug_enabled) Print("gb_logging: buffer full, dropping oldest");
   }
   LOG_buffer[LOG_buffer_tail] = sql;
   LOG_buffer_tail = (LOG_buffer_tail + 1) % LOG_BUFFER_MAX;
   LOG_buffer_count++;
   return true;
}

string LOG_BufferPop()
{
   if(LOG_buffer_count <= 0) return "";
   string s = LOG_buffer[LOG_buffer_head];
   LOG_buffer[LOG_buffer_head] = "";
   LOG_buffer_head = (LOG_buffer_head + 1) % LOG_BUFFER_MAX;
   LOG_buffer_count--;
   return s;
}

int LOG_BufferCount()
{
   return LOG_buffer_count;
}

void LOG_WriteStatusSimple(const string reason)
{
   string now = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string term_data = TerminalInfoString(TERMINAL_DATA_PATH);
   string term_common = TerminalInfoString(TERMINAL_COMMONDATA_PATH);

   string status_name = "growbuddy_db_status.txt";
   string expected_common_path = term_common + "\\MQL5\\Files\\" + status_name;
   string expected_agent_path = term_data + "\\MQL5\\Files\\" + status_name;

   string header = "---- STATUS ENTRY ----";
   string footer = "---- END ENTRY ----";

   int fh = FileOpen(status_name, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   int err = GetLastError();
   PrintFormat("gb_logging: try FILE_COMMON fh=%d GetLastError=%d expected=%s", fh, err, expected_common_path);
   if(fh >= 0)
   {
      FileSeek(fh, 0, SEEK_END);
      FileWrite(fh, header);
      FileWrite(fh, "time: " + now);
      FileWrite(fh, "reason: " + reason);
      FileWrite(fh, "LOG_db_conninfo: " + LOG_db_conninfo);
      FileWrite(fh, "Terminal DATA path: " + term_data);
      FileWrite(fh, "Terminal COMMONDATA path: " + term_common);
      FileWrite(fh, footer);
      FileClose(fh);
      PrintFormat("gb_logging: wrote status to COMMON Files -> %s", expected_common_path);
      return;
   }

   fh = FileOpen(status_name, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   err = GetLastError();
   PrintFormat("gb_logging: try agent Files fh=%d GetLastError=%d expected=%s", fh, err, expected_agent_path);
   if(fh >= 0)
   {
      FileSeek(fh, 0, SEEK_END);
      FileWrite(fh, header);
      FileWrite(fh, "time: " + now);
      FileWrite(fh, "reason: " + reason);
      FileWrite(fh, "LOG_db_conninfo: " + LOG_db_conninfo);
      FileWrite(fh, "Terminal DATA path: " + term_data);
      FileWrite(fh, "Terminal COMMONDATA path: " + term_common);
      FileWrite(fh, footer);
      FileClose(fh);
      PrintFormat("gb_logging: wrote status to agent Files -> %s", expected_agent_path);
      return;
   }

   PrintFormat("gb_logging: FAILED to write status to both COMMON and agent Files. common_err=%d agent_err=%d", GetLastError(), err);
   Print(header);
   Print("time: " + now);
   Print("reason: " + reason);
   Print("LOG_db_conninfo: " + LOG_db_conninfo);
   Print("Terminal DATA path: " + term_data);
   Print("Terminal COMMONDATA path: " + term_common);
   Print(footer);
}

// ---------------- MySQL helpers ----------------
// LOG_OpenDatabase: uses configured LOG_DB_* globals; returns true if connected
bool LOG_OpenDatabase(const string host = "", const string user = "", const string pass = "", const string database = "", int port = 0, const string socket = "", int clientFlag = -1)
{
   string h = (StringLen(host) > 0) ? host : LOG_DB_HOST;
   string u = (StringLen(user) > 0) ? user : LOG_DB_USER;
   string p = (StringLen(pass) > 0) ? pass : LOG_DB_PASSWORD;
   string db = (StringLen(database) > 0) ? database : LOG_DB_DATABASE;
   int prt = (port > 0) ? port : LOG_DB_PORT;
   string sk = (StringLen(socket) > 0) ? socket : LOG_DB_SOCKET;
   int cf = (clientFlag >= 0) ? clientFlag : LOG_DB_CLIENTFLAG;

   if(LOG_debug_enabled) PrintFormat("gb_logging: MySQL Connect Host=%s User=%s DB=%s Port=%d ClientFlag=%d", h, u, db, prt, cf);

   int conn = MySqlConnect(h, u, p, db, prt, sk, cf);
   if(conn == -1)
   {
      LOG_WriteStatusSimple(StringFormat("MySqlConnect failed: #%d %s (Host=%s User=%s DB=%s Port=%d)", MySqlErrorNumber, MySqlErrorDescription, h, u, db, prt));
      return false;
   }

   LOG_db_handle = conn;
   LOG_db_ready = true;
   LOG_db_conninfo = StringFormat("%s@%s/%s:%d", u, h, db, prt);
   LOG_WriteStatusSimple("DatabaseOpen succeeded (MySQL connect) conninfo: " + LOG_db_conninfo);
   return true;
}

void LOG_CloseDatabase()
{
   if(LOG_db_handle != 0)
   {
      MySqlDisconnect(LOG_db_handle);
      LOG_db_handle = 0;
      LOG_db_ready = false;
   }
}

bool LOG_EnsureTables()
{
   if(!LOG_wrapper_initialized || !LOG_db_ready) return false;

   if(!MySqlExecute(LOG_db_handle, LOG_RUNS_CREATE_SQL)) {
      PrintFormat("gb_logging: CREATE runs failed: #%d %s", MySqlErrorNumber, MySqlErrorDescription);
      return false;
   }
   if(!MySqlExecute(LOG_db_handle, LOG_SIGNALS_CREATE_SQL)) {
      PrintFormat("gb_logging: CREATE signals failed: #%d %s", MySqlErrorNumber, MySqlErrorDescription);
      return false;
   }
   if(!MySqlExecute(LOG_db_handle, LOG_PLANS_CREATE_SQL)) {
      PrintFormat("gb_logging: CREATE plans failed: #%d %s", MySqlErrorNumber, MySqlErrorDescription);
      return false;
   }
   if(!MySqlExecute(LOG_db_handle, LOG_EXECUTIONS_CREATE_SQL)) {
      PrintFormat("gb_logging: CREATE executions failed: #%d %s", MySqlErrorNumber, MySqlErrorDescription);
      return false;
   }
   return true;
}

// ---------------- buffering flush (batch insert) ----------------
int LOG_ExecuteWithRetry(const string sql)
{
   for(int attempt = 0; attempt < LOG_FLUSH_RETRIES; attempt++)
   {
      bool ok = MySqlExecute(LOG_db_handle, sql);
      if(ok) return 0;
      Sleep(LOG_FLUSH_RETRY_MS);
   }
   return -1;
}

int LOG_FlushBufferToDB(int maxStatements = 1000)
{
   if(!LOG_db_ready || LOG_db_handle == 0) return 0;
   if(LOG_buffer_count == 0) return 0;

   int executed = 0;
   bool txn_started = MySqlExecute(LOG_db_handle, "START TRANSACTION");
   if(txn_started == false && LOG_debug_enabled) Print("gb_logging: START TRANSACTION failed or not supported, will execute statements individually");

   int toProcess = MathMin(LOG_buffer_count, maxStatements);
   for(int i = 0; i < toProcess; i++)
   {
      string sql = LOG_BufferPop();
      if(StringLen(sql) == 0) continue;
      int rc = LOG_ExecuteWithRetry(sql);
      if(rc != 0)
      {
         if(txn_started) MySqlExecute(LOG_db_handle, "ROLLBACK");
         LOG_BufferPush(sql);
         PrintFormat("gb_logging: LOG_FlushBufferToDB execute failed sql=%s MySqlError=%d %s", sql, MySqlErrorNumber, MySqlErrorDescription);
         return executed;
      }
      executed++;
   }

   if(txn_started) MySqlExecute(LOG_db_handle, "COMMIT");
   return executed;
}

void LOG_FlushBuffer(int perCallMax = 1000)
{
   if(!LOG_buffer_enabled) return;
   if(!LOG_db_ready)
   {
      if(LOG_debug_enabled) Print("gb_logging: LOG_FlushBuffer called but DB not ready");
      return;
   }

   while(LOG_buffer_count > 0)
   {
      int flushed = LOG_FlushBufferToDB(perCallMax);
      if(flushed <= 0) break;
      Sleep(1);
   }

   if(LOG_debug_enabled) PrintFormat("gb_logging: LOG_FlushBuffer completed remain=%d", LOG_buffer_count);
}

// ---------------- auto flush ----------------
void LOG_StartAutoFlush(int interval_seconds)
{
   if(interval_seconds < 1) interval_seconds = 1;
   LOG_auto_flush_interval = interval_seconds;
   LOG_auto_flush_enabled = true;
   EventSetTimer(interval_seconds);
   if(LOG_debug_enabled) PrintFormat("gb_logging: AutoFlush started interval=%d", interval_seconds);
}

void LOG_StopAutoFlush()
{
   if(LOG_auto_flush_enabled)
   {
      EventKillTimer();
      LOG_auto_flush_enabled = false;
      LOG_auto_flush_interval = 0;
      if(LOG_debug_enabled) Print("gb_logging: AutoFlush stopped");
   }
}

void OnTimer()
{
   if(LOG_auto_flush_enabled) LOG_FlushBuffer();
}

// ---------------- public API ----------------
// helper wrappers for Logging_Init convenience

// call Logging_Init using the module defaults (no need to pass params)
bool Logging_InitDefault(bool enableDebug = true)
{
   return Logging_Init(enableDebug,
                       LOG_DB_HOST, LOG_DB_USER, LOG_DB_PASSWORD,
                       LOG_DB_DATABASE, LOG_DB_PORT, LOG_DB_SOCKET, LOG_DB_CLIENTFLAG);
}

// Logging_Init: optional override parameters; if not provided, uses defaults above
bool Logging_Init(bool enableDebug = true, string host = "", string user = "", string pass = "", string database = "", int port = 0, string socket = "", int clientFlag = -1)
{
   LOG_debug_enabled = enableDebug;
   LOG_buffer_enabled = true;

   bool opened = LOG_OpenDatabase(host, user, pass, database, port, socket, clientFlag);
   if(!opened)
   {
      LOG_wrapper_initialized = true;
      LOG_db_ready = false;
      PrintFormat("gb_logging: MySQL connect failed");
      return false;
   }

   LOG_wrapper_initialized = true;
   LOG_db_ready = true;

   if(!LOG_EnsureTables())
   {
      LOG_WriteStatusSimple("EnsureTables failed on initial open");
      LOG_CloseDatabase();
      Print("gb_logging: EnsureTables failed");
      return false;
   }

   if(LOG_debug_enabled) PrintFormat("gb_logging: initialized MySQL connection DBID=%d conn=%s", LOG_db_handle, LOG_db_conninfo);
   return true;
}

void Logging_Deinit()
{
   LOG_FlushBuffer();
   LOG_CloseDatabase();
   LOG_wrapper_initialized = false;
   LOG_db_ready = false;
   LOG_buffer_enabled = false;
   LOG_StopAutoFlush();
}

// ---------------- inserts etc (rewritten) ----------------
int LOG_ExecBuffered(const string sql)
{
   if(!LOG_buffer_enabled)
   {
      if(LOG_db_ready) {
         return (MySqlExecute(LOG_db_handle, sql) ? 0 : -1);
      }
      return -1;
   }
   bool ok = LOG_BufferPush(sql);
   if(!ok)
   {
      Print("gb_logging: LOG_ExecBuffered failed to push sql to buffer");
      return -1;
   }
   return 0;
}

bool LOG_CreateRun(const string run_key, const string run_name, const string config_json)
{
   if(!LOG_wrapper_initialized || !LOG_buffer_enabled) { Print("gb_logging: LOG_CreateRun aborted - not initialized"); return false; }
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string sql = StringFormat("INSERT IGNORE INTO runs (run_key,name,started_at,config_json) VALUES ('%s','%s','%s','%s')",
                             LOG_SQL_Escape(run_key), LOG_SQL_Escape(run_name), LOG_SQL_Escape(ts), LOG_SQL_Escape(config_json));
   int rc = LOG_ExecBuffered(sql);
   return (rc == 0);
}

bool LOG_InsertSignal(const string run_key, const string decision_id, const string ts_utc, const string tf_iTime, const string symbol, const string timeframe, double tenkan, double kijun, double senkouA, double senkouB, double chikou, int signal, const string reason_json, const string blocked_json, const string extra_json)
{
   if(!LOG_wrapper_initialized || !LOG_buffer_enabled) { Print("gb_logging: LOG_InsertSignal aborted - not initialized"); return false; }

   string sql = StringFormat(
      "INSERT INTO signals (run_key,decision_id,ts_utc,tf_iTime,symbol,timeframe,tenkan,kijun,senkouA,senkouB,chikou,signal,reason_json,blocked_json,extra_json) VALUES ('%s','%s','%s',%s,'%s','%s',%f,%f,%f,%f,%f,%d,'%s','%s','%s')",
      LOG_SQL_Escape(run_key), LOG_SQL_Escape(decision_id), LOG_SQL_Escape(ts_utc),
      (StringLen(tf_iTime)>0 ? ("'" + LOG_SQL_Escape(tf_iTime) + "'") : "NULL"),
      LOG_SQL_Escape(symbol), LOG_SQL_Escape(timeframe), tenkan, kijun, senkouA, senkouB, chikou, signal,
      LOG_SQL_Escape(reason_json), LOG_SQL_Escape(blocked_json), LOG_SQL_Escape(extra_json)
   );

   int rc = LOG_ExecBuffered(sql);
   return (rc == 0);
}

bool LOG_InsertPlan(const string run_key, const string decision_id, const string plan_id, const string ts_utc, const string planned_type, const string side, double volume, double price, double sl, double tp, const string comment, const string effective_params_json, const string extra_json)
{
   if(!LOG_wrapper_initialized || !LOG_buffer_enabled) { Print("gb_logging: LOG_InsertPlan aborted - not initialized"); return false; }

   string sql = StringFormat(
      "INSERT INTO plans (run_key,decision_id,plan_id,ts_utc,planned_type,side,volume,price,sl,tp,comment,effective_params_json,extra_json) VALUES ('%s','%s','%s','%s','%s','%s',%f,%f,%f,%f,'%s','%s','%s')",
      LOG_SQL_Escape(run_key), LOG_SQL_Escape(decision_id), LOG_SQL_Escape(plan_id), LOG_SQL_Escape(ts_utc),
      LOG_SQL_Escape(planned_type), LOG_SQL_Escape(side), volume, price, sl, tp, LOG_SQL_Escape(comment),
      LOG_SQL_Escape(effective_params_json), LOG_SQL_Escape(extra_json)
   );

   int rc = LOG_ExecBuffered(sql);
   return (rc == 0);
}

bool LOG_InsertExecution(const string run_key, const string plan_id, const string ts_utc, const string request_json, const string result_json, int retcode, const string retcode_desc, int order_ticket, double filled_price, double assigned_sl, double assigned_tp)
{
   if(!LOG_wrapper_initialized || !LOG_buffer_enabled) { Print("gb_logging: LOG_InsertExecution aborted - not initialized"); return false; }

   string sql = StringFormat(
      "INSERT INTO executions (run_key,plan_id,ts_utc,request_json,result_json,retcode,retcode_desc,order_ticket,filled_price,assigned_sl,assigned_tp) VALUES ('%s','%s','%s','%s','%s',%d,'%s',%d,%f,%f,%f)",
      LOG_SQL_Escape(run_key), LOG_SQL_Escape(plan_id), LOG_SQL_Escape(ts_utc),
      LOG_SQL_Escape(request_json), LOG_SQL_Escape(result_json), retcode,
      LOG_SQL_Escape(retcode_desc), order_ticket, filled_price, assigned_sl, assigned_tp
   );

   int rc = LOG_ExecBuffered(sql);
   return (rc == 0);
}

string LOG_FormatOrderCommentWithPlan(const string baseComment, const string plan_id)
{
   string combined = baseComment;
   if(StringLen(combined) > 0) combined += "|";
   combined += "plan:" + plan_id;
   if(StringLen(combined) > 64) combined = StringSubstr(combined, 0, 64);
   return combined;
}

// helper: detect absolute path
bool IsAbsolutePath(const string s)
{
   if(StringLen(s) == 0) return false;
   if(StringFind(s, ":") != -1) return true; // contains drive letter
   if(StringSubstr(s, 0, 2) == "\\\\") return true; // UNC path
   return false;
}
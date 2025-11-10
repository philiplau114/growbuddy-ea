#property strict
// growbuddy/logging.mqh
// Centralized logging for GrowBuddy EA (Stage2) - fixed for sqlite.mqh wrapper
// Direct SQLite writes from EA. Uses run_key (string) to correlate run -> signals/plans/executions.
// Behavior: call Logging_Init(true) in OnInit to enable DB writes.
// Requires: sqlite.mqh available and native sqlite DLL allowed by terminal (if sqlite.mqh uses DLL).

#ifndef LOGGING_MQH
#define LOGGING_MQH

#include <sqlite.mqh>

#define DB_DEFAULT_SHORTNAME "GrowBuddy.db" // Database file stored to <TERMINAL_DATA_PATH>\MQL5\Files\SQLite\
#define DB_BUSY_TIMEOUT_MS   5000
#define LOG_FALLBACK_FILE    "GrowBuddy_logs_fallback.txt" // file under growbuddy\logs

// If you want the DB to be cleared at initialization, set this to true (or call LOG_SetClearOnInit(true) at runtime)
#define LOG_CLEAR_ON_INIT    true;

static bool LOG_wrapper_initialized = false;
static bool LOG_db_ready = false;
static bool LOG_debug_enabled = false; // controls whether verbose debug printing occurs
static string LOG_db_fullpath = "";
static int LOG_busy_timeout_ms = DB_BUSY_TIMEOUT_MS;

// control whether to clear DB at init (default from define)
static bool LOG_clear_on_init = LOG_CLEAR_ON_INIT;

// Optional in-memory buffer (enabled when buffer allowed)
static bool LOG_buffer_enabled = false;
#define LOG_BUFFER_MAX 1024
static string LOG_buffer[LOG_BUFFER_MAX];
static int LOG_buffer_head = 0;
static int LOG_buffer_tail = 0;
static int LOG_buffer_count = 0;

// ---------------- Schema (runs/signals/plans/executions) ----------------
static string LOG_RUNS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS runs ("
" run_key TEXT PRIMARY KEY,"
" name TEXT,"
" started_at TEXT,"
" finished_at TEXT,"
" config_json TEXT"
");";

static string LOG_SIGNALS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS signals ("
" id INTEGER PRIMARY KEY AUTOINCREMENT,"
" run_key TEXT NOT NULL,"
" decision_id TEXT NOT NULL,"
" ts_utc TEXT NOT NULL,"
" tf_iTime TEXT,"
" symbol TEXT,"
" timeframe TEXT,"
" tenkan REAL,"
" kijun REAL,"
" senkouA REAL,"
" senkouB REAL,"
" chikou REAL,"
" signal INTEGER,"
" reason_json TEXT,"
" blocked_json TEXT,"
" extra_json TEXT"
");";

static string LOG_PLANS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS plans ("
" id INTEGER PRIMARY KEY AUTOINCREMENT,"
" run_key TEXT NOT NULL,"
" decision_id TEXT NOT NULL,"
" plan_id TEXT NOT NULL,"
" ts_utc TEXT NOT NULL,"
" planned_type TEXT,"
" side TEXT,"
" volume REAL,"
" price REAL,"
" sl REAL,"
" tp REAL,"
" comment TEXT,"
" effective_params_json TEXT,"
" extra_json TEXT"
");";

static string LOG_EXECUTIONS_CREATE_SQL =
"CREATE TABLE IF NOT EXISTS executions ("
" id INTEGER PRIMARY KEY AUTOINCREMENT,"
" run_key TEXT NOT NULL,"
" plan_id TEXT NOT NULL,"
" ts_utc TEXT NOT NULL,"
" request_json TEXT,"
" result_json TEXT,"
" retcode INTEGER,"
" retcode_desc TEXT,"
" order_ticket INTEGER,"
" filled_price REAL,"
" assigned_sl REAL,"
" assigned_tp REAL"
");";

// ----------------- helpers -----------------
string LOG_SQL_Escape(string s)
{
   if(StringLen(s) == 0) return "";
   string out = s;
   StringReplace(out, "'", "''");
   return out;
}

string LOG_GetFallbackFilePath()
{
   // ensure path uses MQL5 Files folder and growbuddy\logs subfolder
   string filesPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\growbuddy\\logs\\";
   return filesPath + LOG_FALLBACK_FILE;
}

void LOG_WriteFallbackLine(string line)
{
   int handle = FileOpen(LOG_GetFallbackFilePath(), FILE_READ|FILE_WRITE|FILE_ANSI);
   if(handle < 0)
   {
      handle = FileOpen(LOG_GetFallbackFilePath(), FILE_WRITE|FILE_ANSI);
      if(handle < 0)
      {
         PrintFormat("gb_logging: fallback FileOpen failed err=%d", GetLastError());
         return;
      }
   }
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " | " + line);
   FileClose(handle);
}

// Thin wrapper to execute SQL and handle errors (returns rc)
// Use sqlite_exec2(db_fname, sql) because sqlite.mqh provides sqlite_exec2 for filename-based exec
int LOG_Exec(string sql)
{
   if(!LOG_wrapper_initialized) return -1;
   if(StringLen(LOG_db_fullpath) == 0) return -1;
   int rc = sqlite_exec2(LOG_db_fullpath, sql);
   return rc;
}

// Ensure DB and tables are ready (safe to call multiple times)
bool LOG_EnsureTables()
{
   if(!LOG_wrapper_initialized) return false;
   if(StringLen(LOG_db_fullpath) == 0) return false;

   int rc = sqlite_exec2(LOG_db_fullpath, LOG_RUNS_CREATE_SQL);
   if(rc != 0) { PrintFormat("gb_logging: CREATE runs failed rc=%d", rc); return false; }

   rc = sqlite_exec2(LOG_db_fullpath, LOG_SIGNALS_CREATE_SQL);
   if(rc != 0) { PrintFormat("gb_logging: CREATE signals failed rc=%d", rc); return false; }

   rc = sqlite_exec2(LOG_db_fullpath, LOG_PLANS_CREATE_SQL);
   if(rc != 0) { PrintFormat("gb_logging: CREATE plans failed rc=%d", rc); return false; }

   rc = sqlite_exec2(LOG_db_fullpath, LOG_EXECUTIONS_CREATE_SQL);
   if(rc != 0) { PrintFormat("gb_logging: CREATE executions failed rc=%d", rc); return false; }

   LOG_db_ready = true;
   return true;
}

// Buffer helpers (ring buffer)
bool LOG_BufferPush(string rowSql)
{
   if(!LOG_buffer_enabled) return false;
   if(LOG_buffer_count >= LOG_BUFFER_MAX) return false;
   LOG_buffer[LOG_buffer_tail] = rowSql;
   LOG_buffer_tail = (LOG_buffer_tail + 1) % LOG_BUFFER_MAX;
   LOG_buffer_count++;
   return true;
}
string LOG_BufferPop()
{
   if(LOG_buffer_count <= 0) return "";
   string row = LOG_buffer[LOG_buffer_head];
   LOG_buffer[LOG_buffer_head] = "";
   LOG_buffer_head = (LOG_buffer_head + 1) % LOG_BUFFER_MAX;
   LOG_buffer_count--;
   return row;
}

void LOG_FlushBuffer()
{
   if(!LOG_buffer_enabled || LOG_buffer_count <= 0) return;
   if(!LOG_wrapper_initialized || !LOG_db_ready)
   {
      while(LOG_buffer_count > 0)
      {
         string s = LOG_BufferPop();
         LOG_WriteFallbackLine("BUFFER_FLUSH: " + s);
      }
      return;
   }

   int attempts = 0;
   while(LOG_buffer_count > 0 && attempts < LOG_BUFFER_MAX)
   {
      string sql = LOG_BufferPop();
      if(StringLen(sql) == 0) { attempts++; continue; }
      int rc = LOG_Exec(sql);
      if(rc != 0)
      {
         LOG_WriteFallbackLine("BUFFER_EXEC_FAIL rc=" + IntegerToString(rc) + " sql=" + sql);
         break;
      }
      attempts++;
   }
}

// ----------------- New: DB Clear API (only for GrowBuddy tables) -----------------
bool LOG_ClearDatabase()
{
   if(!LOG_wrapper_initialized)
   {
      Print("gb_logging: LOG_ClearDatabase aborted - wrapper not initialized");
      return false;
   }
   if(StringLen(LOG_db_fullpath) == 0)
   {
      Print("gb_logging: LOG_ClearDatabase aborted - db path empty");
      return false;
   }

   sqlite_exec2(LOG_db_fullpath, "DELETE FROM runs;");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM signals;");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM plans;");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM executions;");

   sqlite_exec2(LOG_db_fullpath, "DELETE FROM sqlite_sequence WHERE name='runs';");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM sqlite_sequence WHERE name='signals';");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM sqlite_sequence WHERE name='plans';");
   sqlite_exec2(LOG_db_fullpath, "DELETE FROM sqlite_sequence WHERE name='executions';");

   int rc = sqlite_exec2(LOG_db_fullpath, "VACUUM;");
   if(rc != 0)
   {
      PrintFormat("gb_logging: LOG_ClearDatabase VACUUM failed rc=%d", rc);
      LOG_WriteFallbackLine("CLEAR_DB_VACUUM_FAIL rc=" + IntegerToString(rc));
   }

   PrintFormat("gb_logging: LOG_ClearDatabase succeeded for DB=%s", LOG_db_fullpath);
   return true;
}

void LOG_SetClearOnInit(bool enable)
{
   LOG_clear_on_init = enable;
}

// ----------------- Public API -----------------
// Note: sqlite_get_fname signature used below is: bool sqlite_get_fname(string db_fname, string& path, int pathlen)
bool Logging_Init(bool enableDebug = true, string dbShortName = DB_DEFAULT_SHORTNAME, int busyTimeoutMs = DB_BUSY_TIMEOUT_MS)
{
   if(LOG_wrapper_initialized && LOG_db_ready)
   {
      LOG_debug_enabled = enableDebug;
      LOG_buffer_enabled = enableDebug;
      return true;
   }

   // initialize sqlite wrapper - sqlite_initialize returns 0 on success in this wrapper
   int init_rc = sqlite_initialize(TerminalInfoString(TERMINAL_DATA_PATH));
   if(init_rc != 0)
   {
      PrintFormat("gb_logging: sqlite_initialize() failed rc=%d", init_rc);
      LOG_wrapper_initialized = false;
      LOG_db_ready = false;
      LOG_debug_enabled = enableDebug;
      LOG_buffer_enabled = enableDebug;
      return false;
   }

   LOG_wrapper_initialized = true;
   LOG_debug_enabled = enableDebug;
   LOG_buffer_enabled = enableDebug;
   LOG_busy_timeout_ms = busyTimeoutMs;

   string resolved = "";
   // try to get path using sqlite_get_fname (3-arg signature)
   bool fname_ok = sqlite_get_fname(dbShortName, resolved, 1024);
   if(!fname_ok || StringLen(resolved) == 0)
   {
      string termData = TerminalInfoString(TERMINAL_DATA_PATH);
      resolved = termData + "\\MQL5\\Files\\SQLite\\" + dbShortName;
   }
   LOG_db_fullpath = resolved;

   sqlite_set_busy_timeout(LOG_busy_timeout_ms);
   // wrapper provides sqlite_set_journal_mode which maps to PRAGMA journaling
   sqlite_set_journal_mode("WAL");
   sqlite_exec2(LOG_db_fullpath, "PRAGMA synchronous=NORMAL;");

   if(!LOG_EnsureTables())
   {
      PrintFormat("gb_logging: EnsureTables failed for %s", LOG_db_fullpath);
      LOG_db_ready = false;
      return false;
   }

   if(LOG_clear_on_init)
   {
      bool cleared = LOG_ClearDatabase();
      if(!cleared) Print("gb_logging: warning - attempted to clear DB on init but failed");
   }

   LOG_db_ready = true;
   PrintFormat("gb_logging: initialized DB=%s debug=%s", LOG_db_fullpath, (LOG_debug_enabled ? "true":"false"));
   return true;
}

void Logging_Deinit()
{
   if(LOG_buffer_enabled) LOG_FlushBuffer();
   // no global finalize function in this sqlite wrapper; leave DB file closed by wrapper internals
   LOG_wrapper_initialized = false;
   LOG_db_ready = false;
   LOG_db_fullpath = "";
   LOG_debug_enabled = false;
   LOG_buffer_enabled = false;
}

// ----------------- New APIs for runs / signals / plans / executions -----------------

bool LOG_CreateRun(string run_key, string run_name, string config_json)
{
   if(!LOG_wrapper_initialized || !LOG_db_ready)
   {
      PrintFormat("gb_logging: LOG_CreateRun fallback - run_key=%s", run_key);
      LOG_WriteFallbackLine("CREATE_RUN_FALLBACK run_key=" + run_key + " name=" + run_name);
      return false;
   }

   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string sql = StringFormat(
      "INSERT OR IGNORE INTO runs (run_key,name,started_at,config_json) VALUES ('%s','%s','%s','%s');",
      LOG_SQL_Escape(run_key),
      LOG_SQL_Escape(run_name),
      LOG_SQL_Escape(ts),
      LOG_SQL_Escape(config_json)
   );

   if(LOG_buffer_enabled)
   {
      bool pushed = LOG_BufferPush(sql);
      if(pushed) return true;
   }

   int rc = LOG_Exec(sql);
   if(rc != 0)
   {
      LOG_WriteFallbackLine("CREATE_RUN_FAIL rc=" + IntegerToString(rc) + " sql=" + sql);
      return false;
   }
   return true;
}

bool LOG_InsertSignal(string run_key, string decision_id, string ts_utc, string tf_iTime, string symbol, string timeframe, double tenkan, double kijun, double senkouA, double senkouB, double chikou, int signal, string reason_json, string blocked_json, string extra_json)
{
   if(!LOG_wrapper_initialized || !LOG_db_ready)
   {
      PrintFormat("gb_logging: LOG_InsertSignal fallback run_key=%s decision=%s", run_key, decision_id);
      LOG_WriteFallbackLine("INSERT_SIGNAL_FALLBACK run_key=" + run_key + " decision=" + decision_id);
      return false;
   }

   string sql = StringFormat(
      "INSERT INTO signals (run_key,decision_id,ts_utc,tf_iTime,symbol,timeframe,tenkan,kijun,senkouA,senkouB,chikou,signal,reason_json,blocked_json,extra_json) VALUES ('%s','%s','%s','%s','%s','%s',%f,%f,%f,%f,%f,%d,'%s','%s','%s');",
      LOG_SQL_Escape(run_key),
      LOG_SQL_Escape(decision_id),
      LOG_SQL_Escape(ts_utc),
      LOG_SQL_Escape(tf_iTime),
      LOG_SQL_Escape(symbol),
      LOG_SQL_Escape(timeframe),
      tenkan,
      kijun,
      senkouA,
      senkouB,
      chikou,
      signal,
      LOG_SQL_Escape(reason_json),
      LOG_SQL_Escape(blocked_json),
      LOG_SQL_Escape(extra_json)
   );

   if(LOG_buffer_enabled)
   {
      bool pushed = LOG_BufferPush(sql);
      if(pushed) return true;
   }

   int rc = LOG_Exec(sql);
   if(rc != 0)
   {
      LOG_WriteFallbackLine("SIGNAL_INSERT_FAIL rc=" + IntegerToString(rc) + " sql=" + sql);
      return false;
   }
   return true;
}

bool LOG_InsertPlan(string run_key, string decision_id, string plan_id, string ts_utc, string planned_type, string side, double volume, double price, double sl, double tp, string comment, string effective_params_json, string extra_json)
{
   if(!LOG_wrapper_initialized || !LOG_db_ready)
   {
      PrintFormat("gb_logging: LOG_InsertPlan fallback run_key=%s plan=%s", run_key, plan_id);
      LOG_WriteFallbackLine("INSERT_PLAN_FALLBACK run_key=" + run_key + " plan=" + plan_id);
      return false;
   }

   string sql = StringFormat(
      "INSERT INTO plans (run_key,decision_id,plan_id,ts_utc,planned_type,side,volume,price,sl,tp,comment,effective_params_json,extra_json) VALUES ('%s','%s','%s','%s','%s','%s',%f,%f,%f,%f,'%s','%s','%s');",
      LOG_SQL_Escape(run_key),
      LOG_SQL_Escape(decision_id),
      LOG_SQL_Escape(plan_id),
      LOG_SQL_Escape(ts_utc),
      LOG_SQL_Escape(planned_type),
      LOG_SQL_Escape(side),
      volume,
      price,
      sl,
      tp,
      LOG_SQL_Escape(comment),
      LOG_SQL_Escape(effective_params_json),
      LOG_SQL_Escape(extra_json)
   );

   if(LOG_buffer_enabled)
   {
      bool pushed = LOG_BufferPush(sql);
      if(pushed) return true;
   }

   int rc = LOG_Exec(sql);
   if(rc != 0)
   {
      LOG_WriteFallbackLine("PLAN_INSERT_FAIL rc=" + IntegerToString(rc) + " sql=" + sql);
      return false;
   }
   return true;
}

bool LOG_InsertExecution(string run_key, string plan_id, string ts_utc, string request_json, string result_json, int retcode, string retcode_desc, int order_ticket, double filled_price, double assigned_sl, double assigned_tp)
{
   if(!LOG_wrapper_initialized || !LOG_db_ready)
   {
      PrintFormat("gb_logging: LOG_InsertExecution fallback plan=%s", plan_id);
      LOG_WriteFallbackLine("INSERT_EXEC_FALLBACK plan=" + plan_id);
      return false;
   }

   string sql = StringFormat(
      "INSERT INTO executions (run_key,plan_id,ts_utc,request_json,result_json,retcode,retcode_desc,order_ticket,filled_price,assigned_sl,assigned_tp) VALUES ('%s','%s','%s','%s','%s',%d,'%s',%d,%f,%f,%f);",
      LOG_SQL_Escape(run_key),
      LOG_SQL_Escape(plan_id),
      LOG_SQL_Escape(ts_utc),
      LOG_SQL_Escape(request_json),
      LOG_SQL_Escape(result_json),
      retcode,
      LOG_SQL_Escape(retcode_desc),
      order_ticket,
      filled_price,
      assigned_sl,
      assigned_tp
   );

   if(LOG_buffer_enabled)
   {
      bool pushed = LOG_BufferPush(sql);
      if(pushed) return true;
   }

   int rc = LOG_Exec(sql);
   if(rc != 0)
   {
      LOG_WriteFallbackLine("EXEC_INSERT_FAIL rc=" + IntegerToString(rc) + " sql=" + sql);
      return false;
   }
   return true;
}

string LOG_FormatOrderCommentWithPlan(string baseComment, string plan_id)
{
   string combined = baseComment;
   if(StringLen(combined) > 0) combined += "|";
   combined += "plan:" + plan_id;
   if(StringLen(combined) > 64) combined = StringSubstr(combined, 0, 64);
   return combined;
}

#endif // LOGGING_MQH
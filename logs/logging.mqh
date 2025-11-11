// logging.mqh - revised: update snapshot only when signal is written + per-symbol snapshot map
#property strict

// ---------------- configurable ----------------
static bool    LOG_debug = true;
static bool    LOG_buffer_enabled = true;
static int     LOG_batch_size = 100;
static int     LOG_flush_interval = 2;
static string  LOG_file_prefix = "gb_run_";
static string  LOG_file_ext = ".jsonl";
static int     LOG_buffer_capacity = 4096;
static int     LOG_file_open_retries = 3;
static int     LOG_file_open_retry_ms = 200;
static int     LOG_max_filename_length = 120;

// ---------------- internal state ----------------
static string  LOG_buffer[];
static int     LOG_head = 0;
static int     LOG_tail = 0;
static int     LOG_count = 0;

static bool    LOG_auto_flush_enabled = false;
static string  LOG_current_runkey = "";
static string  LOG_current_filename = "";

// ---------------- filter + per-symbol snapshot ----------------
static int LOG_keys_capacity = 512;
static string   LOG_keys[];           // key = symbol + "|" + timeframe
static datetime LOG_last_tf[];
static int      LOG_last_signal[];    // last logged signal value for that key
static int      LOG_keys_count = 0;

// per-key snapshot arrays (store last written signal context per symbol|timeframe)
static string LOG_last_signal_decision_id[];   // per-key
static int    LOG_last_signal_value[];         // per-key
static string LOG_last_signal_tf_iTime[];      // per-key

// legacy global snapshot kept for backward compatibility (but updated only when a signal is written)
static string LOG_last_signal_decision_id_global = "";
static int    LOG_last_signal_value_global = 0;
static string LOG_last_signal_tf_iTime_global = "";
static string LOG_last_signal_symbol_global = "";
static string LOG_last_signal_timeframe_global = "";

// initialize
void LOG_FilterInit(int keysCap = 512)
{
   if(keysCap > 0) LOG_keys_capacity = keysCap;
   ArrayResize(LOG_keys, LOG_keys_capacity);
   ArrayResize(LOG_last_tf, LOG_keys_capacity);
   ArrayResize(LOG_last_signal, LOG_keys_capacity);
   ArrayResize(LOG_last_signal_decision_id, LOG_keys_capacity);
   ArrayResize(LOG_last_signal_value, LOG_keys_capacity);
   ArrayResize(LOG_last_signal_tf_iTime, LOG_keys_capacity);
   LOG_keys_count = 0;
   for(int i=0;i<LOG_keys_capacity;i++)
   {
      LOG_keys[i] = "";
      LOG_last_tf[i] = 0;
      LOG_last_signal[i] = 0;
      LOG_last_signal_decision_id[i] = "";
      LOG_last_signal_value[i] = 0;
      LOG_last_signal_tf_iTime[i] = "";
   }
   // init globals
   LOG_last_signal_decision_id_global = "";
   LOG_last_signal_value_global = 0;
   LOG_last_signal_tf_iTime_global = "";
   LOG_last_signal_symbol_global = "";
   LOG_last_signal_timeframe_global = "";
}

// find index if exists, else -1 (no creation)
int LOG_FindKeyIndexNoCreate(const string key)
{
   if(StringLen(key) == 0) return -1;
   for(int i=0;i<LOG_keys_count;i++)
   {
      if(LOG_keys[i] == key) return i;
   }
   return -1;
}

// find or create index for key (symbol|timeframe)
int LOG_FindOrCreateKeyIndex(const string key)
{
   if(StringLen(key) == 0) return(-1);
   for(int i=0;i<LOG_keys_count;i++)
   {
      if(LOG_keys[i] == key) return i;
   }
   if(LOG_keys_count < LOG_keys_capacity)
   {
      LOG_keys[LOG_keys_count] = key;
      LOG_last_tf[LOG_keys_count] = 0;
      LOG_last_signal[LOG_keys_count] = 0;
      LOG_last_signal_decision_id[LOG_keys_count] = "";
      LOG_last_signal_value[LOG_keys_count] = 0;
      LOG_last_signal_tf_iTime[LOG_keys_count] = "";
      LOG_keys_count++;
      return LOG_keys_count - 1;
   }
   // capacity full -> replace a random slot (rare)
   int idx = MathRand() % LOG_keys_capacity;
   LOG_keys[idx] = key;
   LOG_last_tf[idx] = 0;
   LOG_last_signal[idx] = 0;
   LOG_last_signal_decision_id[idx] = "";
   LOG_last_signal_value[idx] = 0;
   LOG_last_signal_tf_iTime[idx] = "";
   return idx;
}

// Combined rule: first-per-candle OR state-change
bool ShouldLogSignal_Combined(const string tf_iTime, const string symbol, const string timeframe, const int signal_value)
{
   // if symbol or timeframe missing, be conservative and log
   if(StringLen(symbol) == 0 || StringLen(timeframe) == 0) return true;

   string key = symbol + "|" + timeframe;
   int idx = LOG_FindOrCreateKeyIndex(key);
   if(idx < 0) return true;

   datetime dt = 0;
   if(StringLen(tf_iTime) > 0)
      dt = StringToTime(tf_iTime);

   if(dt != 0)
   {
      if(LOG_last_tf[idx] != dt)
      {
         LOG_last_tf[idx] = dt;
         LOG_last_signal[idx] = signal_value;
         return true;
      }
      else
      {
         if(LOG_last_signal[idx] != signal_value)
         {
            LOG_last_signal[idx] = signal_value;
            return true;
         }
         return false;
      }
   }
   else
   {
      if(LOG_last_signal[idx] != signal_value)
      {
         LOG_last_signal[idx] = signal_value;
         return true;
      }
      return false;
   }
}

// helper: get snapshot for symbol/timeframe (no create)
bool LOG_GetSnapshot(const string symbol, const string timeframe, string &out_decision_id, int &out_value, string &out_tf_iTime)
{
   out_decision_id = "";
   out_value = 0;
   out_tf_iTime = "";
   if(StringLen(symbol) == 0 || StringLen(timeframe) == 0) return false;
   string key = symbol + "|" + timeframe;
   int idx = LOG_FindKeyIndexNoCreate(key);
   if(idx < 0) return false;
   out_decision_id = LOG_last_signal_decision_id[idx];
   out_value = LOG_last_signal_value[idx];
   out_tf_iTime = LOG_last_signal_tf_iTime[idx];
   if(StringLen(out_decision_id) == 0 && out_value == 0 && StringLen(out_tf_iTime) == 0) return false;
   return true;
}

// ---------------- utilities ----------------
string LOG_JsonEscape(const string s)
{
   if(StringLen(s) == 0) return("");
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\r\n", "\\n");
   StringReplace(out, "\n", "\\n");
   StringReplace(out, "\r", "\\n");
   StringReplace(out, "\t", "\\t");
   return out;
}

string LOG_TimestampNow()
{
   string t = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   StringReplace(t, ".", "-");
   return t;
}

bool LOG_IsRawJson(const string s)
{
   string t = TrimString(s);
   if(StringLen(t) == 0) return(false);
   string c = StringSubstr(t, 0, 1);
   return (c == "{" || c == "[");
}

string LOG_JsonField(const string name, const string value, bool isRaw=false)
{
   if(isRaw) return "\"" + name + "\":" + value;
   return "\"" + name + "\":\"" + LOG_JsonEscape(value) + "\"";
}

// ---------------- buffer ops ----------------
void LOG_BufferInit(int capacity = 4096)
{
   LOG_buffer_capacity = capacity;
   ArrayResize(LOG_buffer, LOG_buffer_capacity);
   LOG_head = 0; LOG_tail = 0; LOG_count = 0;
}

bool LOG_BufferPushLine(const string jsonLine)
{
   if(!LOG_buffer_enabled) return(false);
   if(LOG_count >= LOG_buffer_capacity)
   {
      LOG_head = (LOG_head + 1) % LOG_buffer_capacity;
      LOG_count--;
      if(LOG_debug) Print("gb_logging: buffer full, dropping oldest");
   }
   LOG_buffer[LOG_tail] = jsonLine;
   LOG_tail = (LOG_tail + 1) % LOG_buffer_capacity;
   LOG_count++;
   return true;
}

string LOG_BufferPopLine()
{
   if(LOG_count <= 0) return("");
   string s = LOG_buffer[LOG_head];
   LOG_buffer[LOG_head] = "";
   LOG_head = (LOG_head + 1) % LOG_buffer_capacity;
   LOG_count--;
   return s;
}

// Add this to logging.mqh in the "buffer ops" section (after LOG_BufferPopLine)
int LOG_BufferCount()
{
   return LOG_count;
}

// ---------------- file helpers ----------------
string LOG_SanitizeFilenameFragment(const string s)
{
   if(StringLen(s) == 0) return "";
   string out = s;
   StringReplace(out, ":", "-");
   StringReplace(out, "/", "_");
   StringReplace(out, "\\", "_");
   StringReplace(out, "?", "_");
   StringReplace(out, "*", "_");
   StringReplace(out, "\"", "_");
   StringReplace(out, "<", "_");
   StringReplace(out, ">", "_");
   StringReplace(out, "|", "_");
   StringReplace(out, " ", "_");
   int len = StringLen(out);
   string tmp = "";
   for(int i=0;i<len;i++)
   {
      ushort ch = StringGetCharacter(out, i);
      if(ch >= 32) tmp += StringSubstr(out, i, 1);
   }
   out = tmp;
   if(StringLen(out) > LOG_max_filename_length)
      out = StringSubstr(out, 0, LOG_max_filename_length);
   out = TrimString(out);
   if(StringLen(out) == 0) out = "session_" + IntegerToString(TimeCurrent());
   return out;
}

string LOG_MakeRunFilename(const string runkey)
{
   string rk = runkey;
   if(StringLen(rk) == 0) rk = "session_" + IntegerToString(TimeCurrent());
   rk = LOG_SanitizeFilenameFragment(rk);
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   StringReplace(ts, ".", "-");
   StringReplace(ts, ":", "");
   StringReplace(ts, " ", "T");
   string fname = LOG_file_prefix + rk + "_" + ts + "_" + IntegerToString(MathRand() % 100000) + LOG_file_ext;
   if(StringLen(fname) > 240) fname = StringSubstr(fname, 0, 240 - StringLen(LOG_file_ext)) + LOG_file_ext;
   return fname;
}

int LOG_OpenFileAppendCommon(const string fname)
{
   int fh = FileOpen(fname, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(fh >= 0)
   {
      FileSeek(fh, 0, SEEK_END);
      return fh;
   }
   fh = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(fh >= 0) return fh;
   return -1;
}

// ---------------- event builder & public API ----------------
bool LOG_CreateEventLine(const string type, const string run_key, const string id, const string payloadJsonRaw)
{
   // Drop verbose debug events unless LOG_debug enabled
   if(StringLen(type) > 0 && type == "debug") return false;
   
   string ts = LOG_TimestampNow();
   string eventJson = "{";
   eventJson += LOG_JsonField("type", type) + ",";
   eventJson += LOG_JsonField("ts_utc", ts) + ",";
   if(StringLen(run_key) > 0) eventJson += LOG_JsonField("run_key", run_key) + ",";
   if(StringLen(id) > 0) eventJson += LOG_JsonField("id", id) + ",";
   if(LOG_IsRawJson(payloadJsonRaw))
      eventJson += "\"payload\":" + payloadJsonRaw;
   else
      eventJson += LOG_JsonField("payload", payloadJsonRaw);
   eventJson += "}";
   return LOG_BufferPushLine(eventJson);
}

bool Logging_Init(bool enableDebug = true)
{
   LOG_debug = enableDebug;
   LOG_buffer_enabled = true;
   LOG_BufferInit(LOG_buffer_capacity);
   LOG_FilterInit(LOG_keys_capacity);
   if(LOG_debug) PrintFormat("gb_logging: initialized (batch=%d, interval=%d)", LOG_batch_size, LOG_flush_interval);
   return true;
}

void Logging_Deinit()
{
   LOG_FlushBuffer();
   LOG_StopAutoFlush();
   LOG_buffer_enabled = false;
   if(LOG_debug) Print("gb_logging: deinitialized JSONL logging");
}

bool LOG_SetRun(const string run_key)
{
   LOG_FlushBuffer();
   LOG_current_runkey = run_key;
   LOG_current_filename = LOG_MakeRunFilename(LOG_current_runkey);
   if(LOG_debug) PrintFormat("gb_logging: set run '%s' -> file %s", LOG_current_runkey, LOG_current_filename);
   return true;
}

bool LOG_CreateRun(const string run_key, const string run_name, const string config_json)
{
   if(StringLen(LOG_current_runkey) == 0 && StringLen(run_key) > 0) LOG_SetRun(run_key);
   else if(StringLen(LOG_current_runkey) == 0) LOG_SetRun(run_key);
   string ts = LOG_TimestampNow();
   string cfgPart = LOG_IsRawJson(config_json) ? ("\"config\":" + config_json) : ("\"config\":\"" + LOG_JsonEscape(config_json) + "\"");
   string payload = "{" + LOG_JsonField("name", run_name) + "," + LOG_JsonField("started_at", ts) + "," + cfgPart + "}";
   bool ok = LOG_CreateEventLine("run", LOG_current_runkey, run_key, payload);
   if(ok) LOG_ConditionalFlush();
   return ok;
}

// Revised LOG_FormatIsoUtc and LOG_InsertSignal (fix StringReplace usage)
//
// Usage: replace existing LOG_FormatIsoUtc and LOG_InsertSignal in your logging include.

string LOG_FormatIsoUtc(datetime t)
{
   // TimeToString returns "YYYY.MM.DD HH:MM:SS"
   string s = TimeToString(t, TIME_DATE|TIME_SECONDS);
   string date_part = StringSubstr(s, 0, 10); // "YYYY.MM.DD"
   string time_part = StringSubstr(s, 11);   // "HH:MM:SS"

   // StringReplace modifies date_part in-place and returns int (number of replacements)
   // So call it for its side-effect, then use date_part
   StringReplace(date_part, ".", "-");
   string date_fixed = date_part;

   return date_fixed + "T" + time_part + "Z"; // "YYYY-MM-DDTHH:MM:SSZ"
}

bool LOG_InsertSignal(const string run_key, const string decision_id, const string ts_utc, const string tf_iTime, const string symbol, const string timeframe, double tenkan, double kijun, double senkouA, double senkouB, double chikou, int signal, const string reason_json, const string blocked_json, const string extra_json)
{
   if(StringLen(LOG_current_runkey) == 0 && StringLen(run_key) > 0) LOG_SetRun(run_key);

   // 1) Filter first
   bool allow = ShouldLogSignal_Combined(tf_iTime, symbol, timeframe, signal);
   if(!allow)
   {
      // Do not update per-key snapshot if signal will not be written
      return false;
   }

   // 2) Update per-key snapshot (now that we know we will write)
   string key = "";
   if(StringLen(symbol) > 0 && StringLen(timeframe) > 0) key = symbol + "|" + timeframe;
   int idx = -1;
   if(StringLen(key) > 0) idx = LOG_FindOrCreateKeyIndex(key);
   if(idx >= 0)
   {
      LOG_last_signal_decision_id[idx] = decision_id;
      LOG_last_signal_value[idx] = signal;
      LOG_last_signal_tf_iTime[idx] = tf_iTime;
   }
   // legacy globals
   LOG_last_signal_decision_id_global = decision_id;
   LOG_last_signal_value_global = signal;
   LOG_last_signal_tf_iTime_global = tf_iTime;
   LOG_last_signal_symbol_global = symbol;
   LOG_last_signal_timeframe_global = timeframe;

   // 3) Compute UTC timestamps (root fix: use UTC)
   datetime now_utc = (datetime)TimeGMT();               // TimeGMT returns UTC time
   int signal_compute_epoch = (int)now_utc;
   string signal_compute_ts = LOG_FormatIsoUtc(now_utc); // "YYYY-MM-DDTHH:MM:SSZ"

   // 4) Build payload, injecting compute fields
   string payload = "{";
   payload += LOG_JsonField("decision_id", decision_id) + ",";
   payload += LOG_JsonField("ts_utc", ts_utc) + ",";
   if(StringLen(tf_iTime) > 0)
      payload += LOG_JsonField("tf_iTime", tf_iTime) + ",";
   else
      payload += "\"tf_iTime\":null,";

   // inject standardized UTC compute fields
   payload += LOG_JsonField("signal_compute_ts", signal_compute_ts) + ",";
   payload += "\"signal_compute_epoch\":" + IntegerToString(signal_compute_epoch) + ",";

   payload += LOG_JsonField("symbol", symbol) + ",";
   payload += LOG_JsonField("timeframe", timeframe) + ",";
   payload += "\"tenkan\":" + DoubleToString(tenkan, Digits()) + ",";
   payload += "\"kijun\":" + DoubleToString(kijun, Digits()) + ",";
   payload += "\"senkouA\":" + DoubleToString(senkouA, Digits()) + ",";
   payload += "\"senkouB\":" + DoubleToString(senkouB, Digits()) + ",";
   payload += "\"chikou\":" + DoubleToString(chikou, Digits()) + ",";
   payload += "\"signal\":" + IntegerToString(signal) + ",";

   if(LOG_IsRawJson(reason_json)) payload += "\"reason_json\":" + reason_json + ","; else payload += LOG_JsonField("reason_json", reason_json) + ",";
   if(LOG_IsRawJson(blocked_json)) payload += "\"blocked_json\":" + blocked_json + ","; else payload += LOG_JsonField("blocked_json", blocked_json) + ",";
   if(LOG_IsRawJson(extra_json)) payload += "\"extra_json\":" + extra_json; else payload += LOG_JsonField("extra_json", extra_json);

   payload += "}";

   bool ok = LOG_CreateEventLine("signal", LOG_current_runkey, decision_id, payload);
   if(ok) LOG_ConditionalFlush();
   return ok;
}

// LOG_InsertPlan: try to use per-key snapshot based on symbol/timeframe; fallback to global
bool LOG_InsertPlan(const string run_key, const string decision_id, const string plan_id, const string ts_utc, const string planned_type, const string side, double volume, double price, double sl, double tp, const string comment, const string effective_params_json, const string extra_json)
{
   if(StringLen(LOG_current_runkey) == 0 && StringLen(run_key) > 0) LOG_SetRun(run_key);

   // choose used_decision: prefer explicit decision_id param; else try per-key snapshot; else global snapshot
   string used_decision = decision_id;
   int used_value = 0;
   string used_tf = "";
   bool gotSnapshot = false;
   // try per-key snapshot using global symbol/timeframe if available
   if(StringLen(LOG_last_signal_symbol_global) > 0 && StringLen(LOG_last_signal_timeframe_global) > 0)
   {
      gotSnapshot = LOG_GetSnapshot(LOG_last_signal_symbol_global, LOG_last_signal_timeframe_global, used_decision, used_value, used_tf);
   }
   if(StringLen(used_decision) == 0 && !gotSnapshot)
   {
      // fallback to legacy global snapshot if set
      used_decision = LOG_last_signal_decision_id_global;
      used_value = LOG_last_signal_value_global;
      used_tf = LOG_last_signal_tf_iTime_global;
   }

   string payload = "{";
   payload += LOG_JsonField("decision_id", used_decision) + ",";
   payload += LOG_JsonField("plan_id", plan_id) + ",";
   payload += LOG_JsonField("ts_utc", ts_utc) + ",";
   payload += LOG_JsonField("planned_type", planned_type) + ",";
   payload += LOG_JsonField("side", side) + ",";
   payload += "\"volume\":" + DoubleToString(volume, Digits()) + ",";
   payload += "\"price\":" + DoubleToString(price, Digits()) + ",";
   payload += "\"sl\":" + DoubleToString(sl, Digits()) + ",";
   payload += "\"tp\":" + DoubleToString(tp, Digits()) + ",";
   payload += LOG_JsonField("comment", comment) + ",";
   if(LOG_IsRawJson(effective_params_json)) payload += "\"effective_params_json\":" + effective_params_json + ","; else payload += LOG_JsonField("effective_params_json", effective_params_json) + ",";

   // inject symbol/timeframe and snapshot if available (use globals for symbol/timeframe)
   if(StringLen(LOG_last_signal_symbol_global) > 0) payload += LOG_JsonField("symbol", LOG_last_signal_symbol_global) + ",";
   if(StringLen(LOG_last_signal_timeframe_global) > 0) payload += LOG_JsonField("timeframe", LOG_last_signal_timeframe_global) + ",";
   if(StringLen(used_tf) > 0) payload += LOG_JsonField("tf_iTime", used_tf) + ","; else payload += "\"tf_iTime\":null,";
   if(StringLen(used_decision) > 0) payload += LOG_JsonField("signal_decision_id", used_decision) + ",";
   payload += "\"signal_value\":" + IntegerToString(used_value) + ",";

   if(LOG_IsRawJson(extra_json)) payload += "\"extra_json\":" + extra_json; else payload += LOG_JsonField("extra_json", extra_json);
   payload += "}";
   bool ok = LOG_CreateEventLine("plan", LOG_current_runkey, plan_id, payload);
   if(ok) LOG_ConditionalFlush();
   return ok;
}

// LOG_InsertExecution: similar to plan; attach snapshot from per-key or global fallback
bool LOG_InsertExecution(const string run_key, const string plan_id, const string ts_utc, const string request_json, const string result_json, int retcode, const string retcode_desc, int order_ticket, double filled_price, double assigned_sl, double assigned_tp)
{
   if(StringLen(LOG_current_runkey) == 0 && StringLen(run_key) > 0) LOG_SetRun(run_key);

   // choose snapshot
   string used_decision = "";
   int used_value = 0;
   string used_tf = "";
   if(StringLen(LOG_last_signal_symbol_global) > 0 && StringLen(LOG_last_signal_timeframe_global) > 0)
      LOG_GetSnapshot(LOG_last_signal_symbol_global, LOG_last_signal_timeframe_global, used_decision, used_value, used_tf);

   if(StringLen(used_decision) == 0)
   {
      used_decision = LOG_last_signal_decision_id_global;
      used_value = LOG_last_signal_value_global;
      used_tf = LOG_last_signal_tf_iTime_global;
   }

   string payload = "{";
   payload += LOG_JsonField("decision_id", used_decision) + ",";
   payload += LOG_JsonField("plan_id", plan_id) + ",";
   payload += LOG_JsonField("ts_utc", ts_utc) + ",";
   if(LOG_IsRawJson(request_json)) payload += "\"request_json\":" + request_json + ","; else payload += LOG_JsonField("request_json", request_json) + ",";
   if(LOG_IsRawJson(result_json)) payload += "\"result_json\":" + result_json + ","; else payload += LOG_JsonField("result_json", result_json) + ",";
   payload += "\"retcode\":" + IntegerToString(retcode) + ",";
   payload += LOG_JsonField("retcode_desc", retcode_desc) + ",";
   payload += "\"order_ticket\":" + IntegerToString(order_ticket) + ",";
   payload += "\"filled_price\":" + DoubleToString(filled_price, Digits()) + ",";
   payload += "\"assigned_sl\":" + DoubleToString(assigned_sl, Digits()) + ",";
   payload += "\"assigned_tp\":" + DoubleToString(assigned_tp, Digits()) + ",";

   if(StringLen(LOG_last_signal_symbol_global) > 0) payload += LOG_JsonField("symbol", LOG_last_signal_symbol_global) + ",";
   if(StringLen(LOG_last_signal_timeframe_global) > 0) payload += LOG_JsonField("timeframe", LOG_last_signal_timeframe_global) + ",";
   if(StringLen(used_tf) > 0) payload += LOG_JsonField("tf_iTime", used_tf) + ","; else payload += "\"tf_iTime\":null,";
   if(StringLen(used_decision) > 0) payload += LOG_JsonField("signal_decision_id", used_decision) + ",";
   payload += "\"signal_value\":" + IntegerToString(used_value) + ",";

   payload += "\"_snapshot_injected\":\"1\"";
   payload += "}";

   bool ok = LOG_CreateEventLine("execution", LOG_current_runkey, plan_id, payload);
   if(ok) LOG_ConditionalFlush();
   return ok;
}

// ---------------- flush to file (per-run file, append) ----------------
int LOG_FlushBuffer(int perCallMax = 1000)
{
   if(!LOG_buffer_enabled) return 0;
   if(LOG_count == 0) return 0;
   if(StringLen(LOG_current_filename) == 0)
   {
      if(StringLen(LOG_current_runkey) == 0) LOG_SetRun("");
      LOG_current_filename = LOG_MakeRunFilename(LOG_current_runkey);
      if(LOG_debug) PrintFormat("gb_logging: creating run file %s", LOG_current_filename);
   }

   int toProcess = MathMin(LOG_count, perCallMax);
   int wrote = 0;
   int fh = -1;
   for(int attempt=0; attempt<LOG_file_open_retries; attempt++)
   {
      fh = LOG_OpenFileAppendCommon(LOG_current_filename);
      if(fh >= 0) break;
      Sleep(LOG_file_open_retry_ms);
   }

   if(fh < 0)
   {
      string fallback = LOG_file_prefix + "orphan_" + IntegerToString(TimeCurrent()) + "_" + IntegerToString(MathRand() % 100000) + LOG_file_ext;
      if(LOG_debug) PrintFormat("gb_logging: cannot open run file %s; attempting fallback %s (GetLastError=%d)", LOG_current_filename, fallback, GetLastError());
      fh = LOG_OpenFileAppendCommon(fallback);
      if(fh >= 0) LOG_current_filename = fallback;
   }

   if(fh < 0)
   {
      if(LOG_debug) PrintFormat("gb_logging: failed to open file after retries (GetLastError=%d). Dropping up to %d events.", GetLastError(), toProcess);
      for(int i=0;i<toProcess;i++) { LOG_BufferPopLine(); }
      return 0;
   }

   for(int i = 0; i < toProcess; i++)
   {
      string line = LOG_BufferPopLine();
      if(StringLen(line) == 0) continue;
      FileWrite(fh, line);
      wrote++;
   }
   FileClose(fh);
   if(LOG_debug) PrintFormat("gb_logging: flushed %d events -> %s", wrote, LOG_current_filename);
   return wrote;
}

// auto-flush
void LOG_StartAutoFlush(int interval_seconds)
{
   if(interval_seconds < 1) interval_seconds = 1;
   LOG_flush_interval = interval_seconds;
   LOG_auto_flush_enabled = true;
   EventSetTimer(interval_seconds);
   if(LOG_debug) PrintFormat("gb_logging: AutoFlush started interval=%d", LOG_flush_interval);
}

void LOG_StopAutoFlush()
{
   if(LOG_auto_flush_enabled)
   {
      EventKillTimer();
      LOG_auto_flush_enabled = false;
      if(LOG_debug) Print("gb_logging: AutoFlush stopped");
   }
}

void OnTimer()
{
   if(LOG_auto_flush_enabled) LOG_FlushBuffer(LOG_batch_size);
}

string LOG_FormatOrderCommentWithPlan(const string baseComment, const string plan_id)
{
   string combined = baseComment;
   if(StringLen(combined) > 0) combined += "|";
   combined += "plan:" + plan_id;
   if(StringLen(combined) > 64) combined = StringSubstr(combined, 0, 64);
   return combined;
}

void LOG_ConditionalFlush()
{
   if(LOG_BufferCount() >= LOG_batch_size) LOG_FlushBuffer(LOG_batch_size);
}
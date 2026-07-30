//+------------------------------------------------------------------+
//|                   RRM_ShowRealPaths.mq5                          |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

void OnStart()
{
   // installation path
   Print("→ INSTALLATION_PATH    = ", TerminalInfoString(TERMINAL_PATH));
   // global common data (all terminals share this)
   Print("→ COMMON_DATA_FOLDER   = ", TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   // **THIS** is the profile‐specific Data Folder where your MQL5\Include belongs
   Print("→ DATA_FOLDER_PATH     = ", TerminalInfoString(TERMINAL_DATA_PATH));
}

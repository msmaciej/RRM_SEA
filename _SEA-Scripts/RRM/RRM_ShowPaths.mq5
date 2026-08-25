//+------------------------------------------------------------------+
//|                        RRM_ShowPaths.mq5                        |
//|   Prints the MT5 installation and data‐folder paths              |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict
void OnStart()
{
   // Where the terminal EXE lives
   Print("→ INSTALLATION_PATH = ", TerminalInfoString(TERMINAL_PATH));
   // Where MT5 looks for your MQL5\Include\… folders
   Print("→ DATA_FOLDER       = ", TerminalInfoString(TERMINAL_DATA_PATH));
}

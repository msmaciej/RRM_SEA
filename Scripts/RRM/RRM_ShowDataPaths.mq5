//+------------------------------------------------------------------+
//|            RRM_ShowDataPaths.mq5                                 |
//|   Print MT5’s real INSTALLATION and DATA paths                   |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict
void OnStart()
{
   // DATA_PATH is where the program files live
   Print("→ DATA_PATH = ", DATA_PATH);
   // TERMINAL_DATA_PATH is where your MQL5\Include etc. must go
   Print("→ TERMINAL_DATA_PATH = ", TerminalInfoString(TERMINAL_DATA_PATH));
}

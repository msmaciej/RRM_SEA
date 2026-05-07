//+------------------------------------------------------------------+
//| SEA_ChartMarkers.mqh                                             |
//| Chart visualization for SL levels (Swing & Fractal)             |
//+------------------------------------------------------------------+
#property copyright "RRM_SEA"
#property strict

class CChartMarkers {
private:
   string m_symbol;
   bool   m_show_swing;
   bool   m_show_fractal;
   int    m_lookback;
   bool   m_show_labels;
   int    m_h_fractals;

   // Bar tracking to update only once per bar
   datetime m_last_update;

public:
   CChartMarkers() : m_symbol(""), m_show_swing(false), m_show_fractal(false),
                     m_lookback(50), m_show_labels(true), m_h_fractals(INVALID_HANDLE),
                     m_last_update(0) {}

   ~CChartMarkers() {
      if(m_h_fractals != INVALID_HANDLE) { IndicatorRelease(m_h_fractals); m_h_fractals = INVALID_HANDLE; }
   }

   void Init(string symbol, bool show_swing, bool show_fractal, int lookback, bool show_labels) {
      m_symbol       = symbol;
      m_show_swing   = show_swing;
      m_show_fractal = show_fractal;
      m_lookback     = lookback;
      m_show_labels  = show_labels;

      if(show_fractal) {
         m_h_fractals = iFractals(m_symbol, PERIOD_CURRENT);
         if(m_h_fractals == INVALID_HANDLE)
            Print("[ChartMarkers] WARNING: iFractals() failed (error=", GetLastError(), "). Fractal markers disabled.");
      }
   }

   void Update(int swing_lookback) {
      // Only update on new bar to avoid performance issues
      datetime current_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(current_bar == m_last_update) return;
      m_last_update = current_bar;

      // Clean old markers first
      CleanOldMarkers();

      // Draw swing markers
      if(m_show_swing) {
         DrawSwingMarkers(swing_lookback);
      }

      // Draw fractal markers
      if(m_show_fractal) {
         DrawFractalMarkers();
      }
   }

   void CleanOldMarkers() {
      datetime cutoff_time = 0;

      if(m_lookback > 0) {
         cutoff_time = iTime(m_symbol, PERIOD_CURRENT, m_lookback);
      }

      // Remove arrow markers older than lookback period
      int total_objects = ObjectsTotal(0, 0, OBJ_ARROW);
      for(int i = total_objects - 1; i >= 0; i--) {
         string name = ObjectName(0, i, 0, OBJ_ARROW);

         if(StringFind(name, "SwingSL_") == 0 || StringFind(name, "FractalSL_") == 0) {
            if(m_lookback > 0) {
               datetime obj_time = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
               if(obj_time < cutoff_time) {
                  ObjectDelete(0, name);
               }
            }
         }
      }

      // Remove text labels older than lookback period
      total_objects = ObjectsTotal(0, 0, OBJ_TEXT);
      for(int i = total_objects - 1; i >= 0; i--) {
         string name = ObjectName(0, i, 0, OBJ_TEXT);
         if(StringFind(name, "SwingLabel_") == 0 || StringFind(name, "FractalLabel_") == 0) {
            if(m_lookback > 0) {
               datetime obj_time = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
               if(obj_time < cutoff_time) {
                  ObjectDelete(0, name);
               }
            }
         }
      }
   }

   void DrawSwingMarkers(int swing_lookback) {
      if(swing_lookback < 1) swing_lookback = 1;
      int half = MathMax(1, swing_lookback / 2);
      int bars_to_scan = (m_lookback > 0) ? m_lookback : 100;

      // Use a symmetric window [i-half, i+half] to find confirmed swing highs/lows.
      // Bar i is a swing high if it is the highest in the full window around it.
      for(int i = half + 1; i < bars_to_scan - half; i++) {
         int win_start = i - half;   // newer end of the window (lower bar index = more recent)
         int win_count = 2 * half + 1;

         // Swing high: bar i is the highest bar in the symmetric window
         int high_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, win_count, win_start);
         if(high_idx == i) {
            double price = iHigh(m_symbol, PERIOD_CURRENT, i);
            datetime time = iTime(m_symbol, PERIOD_CURRENT, i);
            DrawSwingMarker(time, price, true, i);
         }

         // Swing low: bar i is the lowest bar in the symmetric window
         int low_idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, win_count, win_start);
         if(low_idx == i) {
            double price = iLow(m_symbol, PERIOD_CURRENT, i);
            datetime time = iTime(m_symbol, PERIOD_CURRENT, i);
            DrawSwingMarker(time, price, false, i);
         }
      }
   }

   void DrawSwingMarker(datetime time, double price, bool isHigh, int bar) {
      string name = StringFormat("SwingSL_%d_%s", bar, TimeToString(time, TIME_DATE|TIME_MINUTES));

      if(ObjectFind(0, name) >= 0) return; // Already exists

      if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price)) return;

      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isHigh ? 234 : 233); // Down : Up arrow
      ObjectSetInteger(0, name, OBJPROP_COLOR,     isHigh ? clrCrimson : clrDodgerBlue);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
      ObjectSetInteger(0, name, OBJPROP_BACK,      true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP,
                      StringFormat("Swing %s: %.5f", isHigh ? "High" : "Low", price));

      if(m_show_labels) {
         string label_name = StringFormat("SwingLabel_%d_%s", bar, TimeToString(time, TIME_DATE|TIME_MINUTES));
         if(ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price)) {
            ObjectSetString(0, label_name, OBJPROP_TEXT,     StringFormat("S:%.5f", price));
            ObjectSetInteger(0, label_name, OBJPROP_COLOR,   isHigh ? clrCrimson : clrDodgerBlue);
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, label_name, OBJPROP_ANCHOR,  isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
         }
      }
   }

   void DrawFractalMarkers() {
      if(m_h_fractals == INVALID_HANDLE) return;

      int bars_to_scan = (m_lookback > 0) ? m_lookback : 100;

      for(int i = 5; i < bars_to_scan; i++) {
         // Upper fractals (highs) — buffer 0
         double upper[1];
         if(CopyBuffer(m_h_fractals, 0, i, 1, upper) > 0) {
            if(upper[0] != EMPTY_VALUE && upper[0] > 0.0) {
               datetime time = iTime(m_symbol, PERIOD_CURRENT, i);
               DrawFractalMarker(time, upper[0], true, i);
            }
         }

         // Lower fractals (lows) — buffer 1
         double lower[1];
         if(CopyBuffer(m_h_fractals, 1, i, 1, lower) > 0) {
            if(lower[0] != EMPTY_VALUE && lower[0] > 0.0) {
               datetime time = iTime(m_symbol, PERIOD_CURRENT, i);
               DrawFractalMarker(time, lower[0], false, i);
            }
         }
      }
   }

   void DrawFractalMarker(datetime time, double price, bool isHigh, int bar) {
      string name = StringFormat("FractalSL_%d_%s", bar, TimeToString(time, TIME_DATE|TIME_MINUTES));

      if(ObjectFind(0, name) >= 0) return; // Already exists

      if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price)) return;

      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isHigh ? 242 : 241); // Filled down : up arrow
      ObjectSetInteger(0, name, OBJPROP_COLOR,     isHigh ? clrOrangeRed : clrLimeGreen);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,     3);
      ObjectSetInteger(0, name, OBJPROP_BACK,      false); // Front (more prominent than swing)
      ObjectSetString(0, name, OBJPROP_TOOLTIP,
                      StringFormat("Fractal %s: %.5f", isHigh ? "High" : "Low", price));

      if(m_show_labels) {
         string label_name = StringFormat("FractalLabel_%d_%s", bar, TimeToString(time, TIME_DATE|TIME_MINUTES));
         if(ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price)) {
            ObjectSetString(0, label_name, OBJPROP_TEXT,     StringFormat("F:%.5f", price));
            ObjectSetInteger(0, label_name, OBJPROP_COLOR,   isHigh ? clrOrangeRed : clrLimeGreen);
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, label_name, OBJPROP_ANCHOR,  isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
         }
      }
   }

   void RemoveAll() {
      // Clean all markers when EA is removed
      ObjectsDeleteAll(0, "SwingSL_");
      ObjectsDeleteAll(0, "FractalSL_");
      ObjectsDeleteAll(0, "SwingLabel_");
      ObjectsDeleteAll(0, "FractalLabel_");
   }
};

// #property script_show_inputs
#property strict

// #include <Arrays/Array.mqh>
// void OnInit()
//  { Print("INCLUDES OK"); }

#include <Arrays\ArrayObj.mqh>
void OnInit()
{
   CArrayObj arr;
   int    n = arr.Total();
   PrintFormat("ArrayObj::Total() = %d", n);
}

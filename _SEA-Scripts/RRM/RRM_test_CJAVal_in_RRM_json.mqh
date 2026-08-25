#include <RRM\RRM_json.mqh>
void OnStart()
{
   CJAVal v;
   Print(v.ToInt(123)); // Should print 123, not error
   Print(v.ToBool(false));
   Print(v.ToStrDef("test"));
}

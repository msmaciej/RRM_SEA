#include <RRM\RRM_EAv1.0_CJAVal.mqh>

void OnStart() {
    CJAVal *sessions = new CJAVal();
    sessions.SetType(JDT_OBJECT);

    // Add array node to simulate: sessions->allowed_sessions = ["LDN", "NY"]
    CJAVal *allowed = new CJAVal();
    allowed.SetType(JDT_ARRAY);
    allowed.AddArrayItem(CJAVal::MakeStrNode("LDN"));
    allowed.AddArrayItem(CJAVal::MakeStrNode("NY"));
    sessions.AddKeyValue(CJAVal::MakeStrNode("allowed_sessions"), allowed);

    Print("Allowed sessions:");
    CJAVal *allowedPtr = sessions.At("allowed_sessions");
    if(allowedPtr != NULL) {
        for(int i=0; i<allowedPtr.JsonSize(); i++) {
            CJAVal *itm = allowedPtr.AtIdx(i);
            Print(itm.ToStr());
        }
    } else {
        Print("allowed_sessions not found");
    }

    delete sessions;
}

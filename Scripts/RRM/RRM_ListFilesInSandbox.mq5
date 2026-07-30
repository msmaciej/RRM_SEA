//+------------------------------------------------------------------+
//| RRM_ListFilesInSandbox.mq5 - List files in sandbox (tester/files)|
//+------------------------------------------------------------------+
void OnStart()
{
    string filename;
    int count = 0;
    Print("Listing files in tester sandbox /files/ ...");
    long h = FileFindFirst("*", filename, FILE_READ);
    if (h != INVALID_HANDLE)
    {
        do
        {
            Print("Found file: ", filename);
            count++;
        }
        while (FileFindNext(h, filename));
        FileFindClose(h);
    }
    else
    {
        Print("No files found or error opening directory.");
    }
    Print("Total files found: ", count);
}

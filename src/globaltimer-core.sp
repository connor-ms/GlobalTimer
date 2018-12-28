#include <globaltimer>

#include <sourcemod>
#include <sdktools>

Database g_hDB;
bool     g_bDBLoaded;

enum struct PlayerTimerInfo
{
    bool bInRun;
    int  iTrack;
    int  iStartTick;
}

PlayerTimerInfo g_pInfo[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "[GlobalTimer] Core",
    author = AUTHOR,
    description = "CS:GO bhop timer.",
    version = VERSION,
    url = URL
};

public void OnPluginStart()
{
    SetupDB();
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    CreateNative("StopTimer", Native_StopTimer);

    RegPluginLibrary("globaltimer_core");

    return APLRes_Success;
}

void SetupDB()
{
    Handle hKeyValues = CreateKeyValues("Connection");
    char   sError[128];

    KvSetString(hKeyValues, "driver",   "sqlite");
    KvSetString(hKeyValues, "database", "globaltimer");

    g_hDB = SQL_ConnectCustom(hKeyValues, sError, sizeof(sError), true);

    if (g_hDB == null)
    {
        PrintToServer("%s Error connecting to db (%s)", PREFIX, sError);
        CloseHandle(g_hDB);
        return;
    }

    g_hDB.Query(DB_ErrorHandler, "CREATE TABLE IF NOT EXISTS records(id INTEGER PRIMARY KEY, map TEXT, time REAL, steamid INTEGER, rank INTEGER);", _);

    g_bDBLoaded = true;
    PrintToServer("%s Record database successfully loaded!", PREFIX);

    CloseHandle(hKeyValues);
}

public void OnPlayerLeaveZone(int client, int tick, int track)
{
    if (track == g_pInfo[client].iTrack)
    {
        g_pInfo[client].iStartTick = tick;
        g_pInfo[client].bInRun = true;
    }
}

public void OnPlayerTrackChange(int client)
{
    g_pInfo[client].iTrack = GetPlayerTrack(client);
    PrintToChat(client, "new track: %i", g_pInfo[client].iTrack);
}

public void OnPlayerEnterZone(int client, int tick, int track)
{
    if (track == g_pInfo[client].iTrack + 1 && g_pInfo[client].bInRun)
    {
        char sFormattedTime[64];

        FormatSeconds((GetGameTickCount() - g_pInfo[client].iStartTick) * GetTickInterval(), sFormattedTime, sizeof(sFormattedTime));

        PrintToChat(client, "Finished in %s.", sFormattedTime);

        g_pInfo[client].bInRun = false;
    }
}

public int Native_StopTimer(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return;
    }

    g_pInfo[GetNativeCell(1)].bInRun = false;
}
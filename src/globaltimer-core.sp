#include <globaltimer>

#include <sourcemod>
#include <sdktools>

enum struct PlayerTimerInfo
{
    char  sId64[64];
    bool  bInRun;
    int   iTrack;
    int   iStartTick;
    float fPb[4];
}

PlayerTimerInfo g_pInfo[MAXPLAYERS + 1];

float    g_fRecord[4];

char     g_sMapName[64];

Database g_hDB;

bool     g_bLate;
bool     g_bDBLoaded;

Handle   g_hBeatPbForward;
Handle   g_hFinishedTrackForward;
Handle   g_hTimerStartForward;

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
    g_bDBLoaded = false;
    g_hBeatPbForward        = CreateGlobalForward("OnPlayerBeatPb",        ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hFinishedTrackForward = CreateGlobalForward("OnPlayerFinishedTrack", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hTimerStartForward    = CreateGlobalForward("OnPlayerTimerStart",    ET_Event, Param_Cell, Param_Cell, Param_Cell);

    AddCommandListener(OnTeamJoin, "jointeam");

    SetupDB();

    if (g_bLate)
    {
        for (int i = 1; i < MAXPLAYERS; i++)
        {
            if (IsClientConnected(i))
            {
                OnTeamJoin(i, "", 0);
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    g_bLate = late;

    CreateNative("StopTimer", Native_StopTimer);
    CreateNative("GetPlayerStartTick", Native_GetPlayerStartTick);
    CreateNative("IsPlayerInRun", Native_IsPlayerInRun);

    RegPluginLibrary("globaltimer_core");

    return APLRes_Success;
}

public void OnMapStart()
{
    char sMapNameTemp[128];
    GetCurrentMap(sMapNameTemp, sizeof(sMapNameTemp));

    GetMapDisplayName(sMapNameTemp, g_sMapName, sizeof(g_sMapName));

    GetMapRecord(Track_MainStart);
    GetMapRecord(Track_BonusStart);
}

public Action OnTeamJoin(int client, const char[] command, int args)
{
    GetPlayerInfo(client);

    return Plugin_Continue;
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
        SetFailState("%s Error connecting to db (%s)", PREFIX, sError);
        CloseHandle(g_hDB);
        return;
    }

    g_hDB.Query(DB_ErrorHandler, "CREATE TABLE IF NOT EXISTS records(id INTEGER PRIMARY KEY, map TEXT, id64 TEXT, track INTEGER, time REAL);", _);

    g_bDBLoaded = true;
    PrintToServer("%s Record database successfully loaded!", PREFIX);

    CloseHandle(hKeyValues);
}

void GetMapRecord(int track)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT time, track FROM 'records' WHERE map = '%s' AND track = %i ORDER BY time ASC;", g_sMapName, track);

    g_hDB.Query(DB_GetRecordHandler, sQuery);
}

void GetPlayerInfo(int client)
{
    if (!IsValidClient(client))
    {
        return;
    }

    GetClientAuthId(client, AuthId_SteamID64, g_pInfo[client].sId64, 64);
    
    FindPb(client);
}

void SavePlayerTime(int client)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'records' WHERE id64 = '%s' AND map = '%s' AND track = %i", g_pInfo[client].sId64, g_sMapName, g_pInfo[client].iTrack);

    g_hDB.Query(DB_SaveTimeHandler, sQuery, client);
}

void FindPb(int client)
{
    char sQuery[256];

    if (StrEqual(g_sMapName, ""))
    {
        OnMapStart();
    }

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'records' WHERE id64 = '%s' AND map = '%s'", g_pInfo[client].sId64, g_sMapName);

    g_hDB.Query(DB_FindPbHandler, sQuery, client);
}

void OverwriteTime(int client, int id)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "UPDATE records SET time = %f WHERE id = %i", g_pInfo[client].fPb[g_pInfo[client].iTrack], id);

    g_hDB.Query(DB_ErrorHandler, sQuery, _);
}

public void DB_FindPbHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", PREFIX, error);
        return;
    }

    if (results.RowCount == 0)
    {
        g_pInfo[client].fPb = 0.0;
    }
    else
    {
        while (results.FetchRow())
        {
            if (results.FetchInt(3) == Track_MainStart)
            {
                g_pInfo[client].fPb[Track_MainStart] = results.FetchFloat(4);
            }
            else
            {
                g_pInfo[client].fPb[Track_BonusStart] = results.FetchFloat(4);
            }
        }
    }
}

public void DB_SaveTimeHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", PREFIX, error);
        return;
    }

    char sQuery[256];

    if (results.RowCount == 0)
    {
        Format(sQuery, sizeof(sQuery), "INSERT INTO records(map, id64, track, time) VALUES('%s', '%s', %i, %f)", g_sMapName, g_pInfo[client].sId64, g_pInfo[client].iTrack, g_pInfo[client].fPb[g_pInfo[client].iTrack]);
        g_hDB.Query(DB_ErrorHandler, sQuery, _);
    }
    else
    {
        OverwriteTime(client, results.FetchInt(0));
    }
}

public void DB_GetRecordHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int track = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", PREFIX, error);
        return;
    }

    if (results.RowCount == 0)
    {
        g_fRecord[track] = 0.0;
    }
    else
    {
        g_fRecord[track] = results.FetchFloat(0);
    }
}

public void OnPlayerLeaveZone(int client, int tick, int track)
{
    if (!IsPlayerAlive(client))
    {
        return;
    }

    if (track == g_pInfo[client].iTrack)
    {
        g_pInfo[client].iStartTick = tick;
        g_pInfo[client].bInRun = true;

        Call_StartForward(g_hTimerStartForward);

        Call_PushCell(client);
        Call_PushCell(track);
        Call_PushCell(tick);

        Call_Finish();
    }
}

public void OnPlayerTrackChange(int client)
{
    g_pInfo[client].iTrack = GetPlayerTrack(client);
}

public void OnPlayerEnterZone(int client, int tick, int track)
{
    if (track == g_pInfo[client].iTrack + 1 && g_pInfo[client].bInRun)
    {
        char  sFormattedTime[64];
        float fTime = (GetGameTickCount() - g_pInfo[client].iStartTick) * GetTickInterval();
        float fOldTime = g_pInfo[client].fPb[g_pInfo[client].iTrack];

        FormatSeconds(fTime, sFormattedTime, sizeof(sFormattedTime), true);

        if (fTime < fOldTime || fOldTime == 0.0) // Player beats pb, but not sr
        {
            g_pInfo[client].fPb[g_pInfo[client].iTrack] = fTime;
            SavePlayerTime(client);

            Call_StartForward(g_hBeatPbForward);

            Call_PushCell(client);
            Call_PushCell(tick);
            Call_PushFloat(fOldTime);
            Call_PushFloat(fTime);

            Call_Finish();
        }
        else // Player doesn't beat pb or sr, but finishes the track
        {
            Call_StartForward(g_hFinishedTrackForward);

            Call_PushCell(client);
            Call_PushCell(g_pInfo[client].iTrack);
            Call_PushFloat(fTime);
            Call_PushFloat(g_pInfo[client].fPb[g_pInfo[client].iTrack]);

            Call_Finish();
        }

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

/*
 * All this cancer because I couldn't figure out how
 * to pass PlayerTimerInfo through a native :(
*/

public int Native_GetPlayerStartTick(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return -1;
    }

    return g_pInfo[GetNativeCell(1)].iStartTick;
}

public int Native_IsPlayerInRun(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return -1;
    }

    return g_pInfo[GetNativeCell(1)].bInRun;
}
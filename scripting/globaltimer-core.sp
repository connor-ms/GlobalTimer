#include <globaltimer>

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

enum struct PlayerTimerInfo
{
    char  sId64[64];     // SteamID64 of player
    bool  bInRun;        // Whether or not timer is running
    int   iTrack;        // Track player is running on
    int   iStartTick;    // Tick player left the start zone
    float fPb[4];        // Pb (in seconds) for each track (only 0 and 2 are used, but size is 4 so arrays line up easier)
}

PlayerTimerInfo g_eInfo[MAXPLAYERS + 1];

float    g_fRecord[4];   // Server record for each track, and eventually each style

char     g_sMapName[64];

Database g_hDB;

bool     g_bLate;
bool     g_bDBLoaded;
bool     g_bStylesLoaded;

Handle   g_hBeatSrForward;
Handle   g_hBeatPbForward;
Handle   g_hFinishedTrackForward;
Handle   g_hTimerStartForward;

public Plugin myinfo =
{
    name = "[GlobalTimer] Core",
    author = "Connor",
    description = "CS:GO bhop timer.",
    version = VERSION,
    url = URL
};

public void OnPluginStart()
{
    g_bDBLoaded = false;
    g_hBeatSrForward        = CreateGlobalForward("OnPlayerBeatSr",        ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hBeatPbForward        = CreateGlobalForward("OnPlayerBeatPb",        ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hTimerStartForward    = CreateGlobalForward("OnPlayerTimerStart",    ET_Event, Param_Cell, Param_Cell, Param_Cell);
    g_hFinishedTrackForward = CreateGlobalForward("OnPlayerFinishedTrack", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);

    SetupDB();

    if (g_bLate)
    {
        for (int i = 1; i < MAXPLAYERS; i++)
        {
            if (IsClientConnected(i))
            {
                OnClientPostAdminCheck(i);
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    g_bLate = late;
    
    RegPluginLibrary("globaltimer_core");

    CreateNative("StopTimer", Native_StopTimer);
    CreateNative("GetPlayerStartTick", Native_GetPlayerStartTick);
    CreateNative("IsPlayerInRun", Native_IsPlayerInRun);
    
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    g_bStylesLoaded = LibraryExists("globaltimer_styles");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "globaltimer_styles"))
    {
        g_bStylesLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "globaltimer_styles"))
    {
        g_bStylesLoaded = false;
    }
}

//=================================
// Forwards
//=================================

public void OnMapStart()
{
    /**
     * Get map name (ex: "bhop_<name>").
    */
    char sMapNameTemp[128];
    GetCurrentMap(sMapNameTemp, sizeof(sMapNameTemp));

    GetMapDisplayName(sMapNameTemp, g_sMapName, sizeof(g_sMapName));

    /**
     * Get record for main and bonus track.
     * TODO: Make this into a loop once styles are done
    */

    GetMapRecord(Track_MainStart);
    GetMapRecord(Track_BonusStart);
}

public void OnClientPostAdminCheck(int client)
{
    GetPlayerInfo(client);

    /**
     * Cancel any damage taken
    */

    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    return Plugin_Handled;
}

public void OnPlayerLeaveZone(int client, int tick, int track)
{
    if (!IsPlayerAlive(client))
    {
        return;
    }

    /**
     * Start timer if player left from track start
    */

    if (track == g_eInfo[client].iTrack)
    {
        PrintToChatAll("styles: %b", g_bStylesLoaded);

        g_eInfo[client].iStartTick = tick;
        g_eInfo[client].bInRun = true;

        Call_StartForward(g_hTimerStartForward);

        Call_PushCell(client);
        Call_PushCell(track);
        Call_PushCell(tick);

        Call_Finish();
    }
}

public void OnPlayerTrackChange(int client)
{
    g_eInfo[client].iTrack = GetPlayerTrack(client);
}

public void OnPlayerEnterZone(int client, int tick, int track)
{
    /**
     * If the player enters end zone for correct track
    */

    if (track == g_eInfo[client].iTrack + 1 && g_eInfo[client].bInRun)
    {
        char  sFormattedTime[64];
        float fTime = (GetGameTickCount() - g_eInfo[client].iStartTick) * GetTickInterval();
        float fOldTime = g_eInfo[client].fPb[g_eInfo[client].iTrack];

        FormatSeconds(fTime, sFormattedTime, sizeof(sFormattedTime), true);

        /**
         * Should each be called separately?
         * Ex: if a player beats the SR, should all
         *     3 forwards be called?
        */

        if (fTime < g_fRecord[g_eInfo[client].iTrack] || g_fRecord[g_eInfo[client].iTrack] == 0.0)
        {
            /**
             * Player beats SR
            */
            
            float fOldRecord = g_fRecord[g_eInfo[client].iTrack];

            g_fRecord[g_eInfo[client].iTrack] = fTime;

            Call_StartForward(g_hBeatSrForward);

            Call_PushCell(client);
            Call_PushCell(tick);
            Call_PushFloat(fOldRecord);
            Call_PushFloat(fTime);

            Call_Finish();
        }

        if (fTime < fOldTime || fOldTime == 0.0)
        {
            /**
             * Player beats PB
            */

            g_eInfo[client].fPb[g_eInfo[client].iTrack] = fTime;
            SavePlayerTime(client);

            Call_StartForward(g_hBeatPbForward);

            Call_PushCell(client);
            Call_PushCell(tick);
            Call_PushFloat(fOldTime);
            Call_PushFloat(fTime);

            Call_Finish();
        }
        else
        {
            /**
             * Player finishes track, but doesn't beat PB
            */

            Call_StartForward(g_hFinishedTrackForward);

            Call_PushCell(client);
            Call_PushCell(g_eInfo[client].iTrack);
            Call_PushFloat(fTime);
            Call_PushFloat(g_eInfo[client].fPb[g_eInfo[client].iTrack]);

            Call_Finish();
        }

        g_eInfo[client].bInRun = false;
    }
}

//=================================
// DB
//=================================

void SetupDB()
{
    Handle hKeyValues = CreateKeyValues("Connection");
    char   sError[128];

    KvSetString(hKeyValues, "driver",   "sqlite");
    KvSetString(hKeyValues, "database", "globaltimer");

    g_hDB = SQL_ConnectCustom(hKeyValues, sError, sizeof(sError), true);

    if (g_hDB == null)
    {
        SetFailState("%s Error connecting to db (%s)", g_sPrefix, sError);
        CloseHandle(g_hDB);
        return;
    }

    g_hDB.Query(DB_ErrorHandler, "CREATE TABLE IF NOT EXISTS records(id INTEGER PRIMARY KEY, map TEXT, id64 TEXT, track INTEGER, time REAL, timestamp INTEGER);", _);

    g_bDBLoaded = true;
    PrintToServer("%s Record database successfully loaded!", g_sPrefix);

    CloseHandle(hKeyValues);
}

void GetMapRecord(int track)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT time, track FROM 'records' WHERE map = '%s' AND track = %i ORDER BY time ASC;", g_sMapName, track);

    g_hDB.Query(DB_GetRecordHandler, sQuery, track);
}

void SavePlayerTime(int client)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'records' WHERE id64 = '%s' AND map = '%s' AND track = %i", g_eInfo[client].sId64, g_sMapName, g_eInfo[client].iTrack);

    g_hDB.Query(DB_SaveTimeHandler, sQuery, client);
}

void FindPb(int client)
{
    char sQuery[256];

    if (StrEqual(g_sMapName, ""))
    {
        OnMapStart();
    }

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'records' WHERE id64 = '%s' AND map = '%s'", g_eInfo[client].sId64, g_sMapName);

    g_hDB.Query(DB_FindPbHandler, sQuery, client);
}

void OverwriteTime(int client, int id)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "UPDATE records SET time = %f, timestamp = %i WHERE id = %i", g_eInfo[client].fPb[g_eInfo[client].iTrack], GetTime(), id);

    g_hDB.Query(DB_ErrorHandler, sQuery, _);
}

public void DB_FindPbHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", g_sPrefix, error);
        return;
    }

    if (results.RowCount == 0)
    {
        g_eInfo[client].fPb = 0.0;
    }
    else
    {
        while (results.FetchRow())
        {
            if (results.FetchInt(3) == Track_MainStart)
            {
                g_eInfo[client].fPb[Track_MainStart] = results.FetchFloat(4);
            }
            else
            {
                g_eInfo[client].fPb[Track_BonusStart] = results.FetchFloat(4);
            }
        }
    }
}

public void DB_SaveTimeHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", g_sPrefix, error);
        return;
    }

    char sQuery[256];

    if (results.RowCount == 0)
    {
        Format(sQuery, sizeof(sQuery), "INSERT INTO records(map, id64, track, time, timestamp) VALUES('%s', '%s', %i, %f, %i)", g_sMapName, g_eInfo[client].sId64, g_eInfo[client].iTrack, g_eInfo[client].fPb[g_eInfo[client].iTrack], GetTime());
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
        SetFailState("%s DB error. (%s)", g_sPrefix, error);
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

//=================================
// Other
//=================================

void GetPlayerInfo(int client)
{
    GetClientAuthId(client, AuthId_SteamID64, g_eInfo[client].sId64, 64);
    
    FindPb(client);
}

//=================================
// Natives
//=================================

public int Native_StopTimer(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return;
    }

    g_eInfo[GetNativeCell(1)].bInRun = false;
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

    return g_eInfo[GetNativeCell(1)].iStartTick;
}

public int Native_IsPlayerInRun(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return -1;
    }

    return g_eInfo[GetNativeCell(1)].bInRun;
}
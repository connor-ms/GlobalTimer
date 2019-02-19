#include <globaltimer>

#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>

enum struct PlayerInfo
{
    char  sId64[18];    // SteamID64 of player.
    bool  bInRun;       // Whether the player's timer should be running.
    int   iCurrentZone; // Whether the player's in a zone or not. (-1 = no zone, >0 = zone index)
    float fJumpSpeed;   // Speed from previous jump.
    float fSSJ;         // Player's speed on 6th jump.

    int   iStyle;
    int   iFirstKey;    // For A/D-only, saves the first A or D keypress to decide which style to use.

    int   iTotalChecks;
    int   iGoodChecks;
    float fTotalSpeed;
    float fSpeedChecks;
    float fPrevVel;
};

PlayerInfo g_eInfo[MAXPLAYERS + 1];
RunFrame   g_eCurFrame[MAXPLAYERS + 1];
DB         g_eDB;
Style      g_eStyles[MAXSTYLES];

ArrayList g_aTimes[MAXSTYLES][2];
ArrayList g_aNames[MAXSTYLES][2];

float g_fPb[MAXPLAYERS + 1][MAXSTYLES][2]; // Player's pb for main and bonus tracks.
float g_fSr[MAXSTYLES][2];                 // Server record for main and bonus tracks.

float g_fOrigins[MAXPLAYERS + 1][2][3];
float g_fTracePoint[MAXPLAYERS + 1][3];
float g_fPrevAngles[MAXPLAYERS + 1][3];

int  g_iStyles;

bool g_bLate;

char g_sMapName[128];

Handle g_hBeatSrForward;
Handle g_hBeatPbForward;
Handle g_hFinishTrackForward;
Handle g_hStyleChangeForward;
Handle g_hSrLoaded;
Handle g_hPbLoaded;
Handle g_hOnTimerIncrement;

public Plugin myinfo =
{
    name        = "[GlobalTimer] Core",
    description = "Zone handling for timer.",
    author      = "Connor",
    version     = VERSION,
    url         = URL
};

public void OnPluginStart()
{
    SetupDB();

    g_hOnTimerIncrement   = CreateGlobalForward("OnPlayerTimerIncrement", ET_Event, Param_Cell, Param_Array, Param_Float);

    g_hBeatSrForward      = CreateGlobalForward("OnPlayerBeatSr",         ET_Event, Param_Cell, Param_Cell, Param_Cell,  Param_Float, Param_Float);
    g_hBeatPbForward      = CreateGlobalForward("OnPlayerBeatPb",         ET_Event, Param_Cell, Param_Array, Param_Float);
    g_hFinishTrackForward = CreateGlobalForward("OnPlayerFinishedTrack",  ET_Event, Param_Cell, Param_Array, Param_Float);

    g_hStyleChangeForward = CreateGlobalForward("OnPlayerStyleChange",    ET_Event, Param_Cell, Param_Array);

    g_hSrLoaded           = CreateGlobalForward("OnSrLoaded",             ET_Event, Param_Float, Param_Array);
    g_hPbLoaded           = CreateGlobalForward("OnPbLoaded",             ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Float);

    RegConsoleCmd("sm_style", CMD_Style, "Change bhopping style.");
    RegConsoleCmd("sm_top", CMD_Top, "View top times for the map.");

    AddCommandListener(OnPlayerSay, "say");
    AddCommandListener(OnPlayerSay, "say_team");

    HookEvent("player_jump", OnPlayerJump);
    HookEvent("player_death", OnPlayerDeath);

    LoadStyles();
    
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

    CreateNative("GetPlayerFrame",         Native_GetPlayerFrame);
    CreateNative("GetPlayerCurrentZone",   Native_GetPlayerCurrentZone);
    CreateNative("GetPlayerJumpSpeed",     Native_GetPlayerJumpSpeed);
    CreateNative("GetPlayerPb",            Native_GetPlayerPb);
    CreateNative("GetPlayerStyleSettings", Native_GetPlayerStyleSettings);
    CreateNative("IsPlayerInRun",          Native_IsPlayerInRun);
    CreateNative("StopTimer",              Native_StopTimer);
    CreateNative("GetSr",                  Native_GetSr);
    CreateNative("GetPlacementByTime",     Native_GetPlacementByTime);
    CreateNative("GetTotalTimes",          Native_GetTotalTimes);

    RegPluginLibrary("globaltimer-core");
    
    return APLRes_Success;
}

//=================================
// Forwards
//=================================

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));

    for (int style = 0; style < g_iStyles; style++)
    {
        for (int track = 0; track < 2; track++)
        {
            g_fSr[style][track] = 0.0;

            if (g_aTimes[style][track] != null)
            {
                g_aTimes[style][track].Clear();
            }

            if (g_aNames[style][track] != null)
            {
                g_aNames[style][track].Clear();
            }
        }
    }

    LoadTimes();
}

public void OnClientPostAdminCheck(int client)
{
    g_eInfo[client].bInRun       = false;
    g_eInfo[client].iStyle       = 0;
    g_eInfo[client].fSSJ         = 0.0;
    g_eInfo[client].fPrevVel     = 0.0;
    g_eInfo[client].iTotalChecks = 0;
    g_eInfo[client].iGoodChecks  = 0;
    g_eInfo[client].iFirstKey    = -1;

    g_eCurFrame[client].iTrack   = Track_Main;
    g_eCurFrame[client].fTime    = 0.0;
    
    for (int style = 0; style < MAXSTYLES; style++)
    {
        for (int track = 0; track <= 1; track++)
        {
            g_fPb[client][style][track] = 0.0;
        }
    }
    
    GetPlayerInfo(client);

    SDKHook(client, SDKHook_PostThinkPost, OnPostThink);
    SDKHook(client, SDKHook_OnTakeDamage,  OnTakeDamage);
    SDKHook(client, SDKHook_WeaponDrop,    OnDropWeapon);
}

public void OnGameFrame()
{
    for (int client = 1; client < MAXPLAYERS; client++)
    {
        if (!IsPlayer(client))
        {
            continue;
        }

        if (!g_eInfo[client].bInRun)
        {
            continue;
        }

        Call_StartForward(g_hOnTimerIncrement);

        Call_PushCell(client);
        Call_PushArray(g_eCurFrame[client], sizeof(RunFrame));
        Call_PushFloat(GetGameFrameTime());

        Call_Finish();

        g_eCurFrame[client].fTime += GetGameFrameTime();
    }
}

public void OnPostThink(int client)
{
    g_fOrigins[client][1] = g_fOrigins[client][0];
    GetClientAbsOrigin(client, g_fOrigins[client][0]);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    float fVel[3];

    if (g_eInfo[client].bInRun)
    {
        if (!IsPlayerAlive(client))
        {
            StopTimer(client, false);
        }

        if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
        {
            StopTimer(client, true);
        }

        g_eCurFrame[client].iButtons = buttons;

        GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
        fVel[2] = 0.0;

        if ((!(GetEntityFlags(client) & FL_ONGROUND) || buttons & IN_JUMP))
        {
            if (g_eStyles[g_eInfo[client].iStyle].iAllowForwards == KeyReq_Disabled && (buttons & IN_FORWARD || vel[0] > 0.0))
            {
                vel[0] = 0.0;
                buttons &= ~IN_FORWARD;
            }

            if (g_eStyles[g_eInfo[client].iStyle].iAllowLeft == KeyReq_Disabled && (buttons & IN_MOVELEFT || vel[1] < 0.0))
            {
                vel[1] = 0.0;
                buttons &= ~IN_MOVELEFT;
            }

            if (g_eStyles[g_eInfo[client].iStyle].iAllowRight == KeyReq_Disabled && (buttons & IN_MOVERIGHT || vel[1] > 0.0))
            {
                vel[1] = 0.0;
                buttons &= ~IN_MOVERIGHT;
            }

            if (g_eStyles[g_eInfo[client].iStyle].iAllowBack == KeyReq_Disabled && (buttons & IN_BACK || vel[0] < 0.0))
            {
                vel[0] = 0.0;
                buttons &= ~IN_BACK;
            }

            if (g_eStyles[g_eInfo[client].iStyle].iCustom == CustomStyle_HSW)
            {
                if (!((buttons & (IN_MOVELEFT  | IN_FORWARD)) == (IN_MOVELEFT  | IN_FORWARD)
                   || (buttons & (IN_MOVERIGHT | IN_FORWARD)) == (IN_MOVERIGHT | IN_FORWARD)))
                {
                    vel[0] = 0.0;
                    vel[1] = 0.0;
                }
            }
            else if (g_eStyles[g_eInfo[client].iStyle].iCustom == CustomStyle_ADOnly)
            {
                if (g_eInfo[client].iFirstKey == -1)
                {
                    if (buttons & IN_MOVELEFT)
                    {
                        g_eInfo[client].iFirstKey = 0;
                    }
                    else if (buttons & IN_MOVERIGHT)
                    {
                        g_eInfo[client].iFirstKey = 1;
                    }
                }

                if (g_eInfo[client].iFirstKey == 0) // A-Only
                {
                    if (buttons & IN_MOVERIGHT || vel[1] > 0.0)
                    {
                        vel[1] = 0.0;
                        buttons &= ~IN_MOVERIGHT;
                    }
                }
                else if (g_eInfo[client].iFirstKey == 1) // D-Only
                {
                    if (buttons & IN_MOVELEFT || vel[1] < 0.0)
                    {
                        vel[1] = 0.0;
                        buttons &= ~IN_MOVELEFT;
                    }
                }
            }

            CalculateSync(client, GetVectorLength(fVel), angles);
            g_eCurFrame[client].fSync = float(g_eInfo[client].iGoodChecks) / float(g_eInfo[client].iTotalChecks) * 100.0;
        }

        if (GetVectorLength(fVel) > g_eCurFrame[client].fMaxSpeed)
        {
            g_eCurFrame[client].fMaxSpeed = GetVectorLength(fVel);
        }

        g_eInfo[client].fTotalSpeed += GetVectorLength(fVel);
        g_eInfo[client].fSpeedChecks++;
    }

    return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    return Plugin_Handled;
}

public Action OnDropWeapon(int client, int weapon)
{
    AcceptEntityInput(weapon, "Kill");

    return Plugin_Continue;
}

public Action OnPlayerSay(int client, const char[] command, int args)
{
    char sArg[64];
    GetCmdArgString(sArg, sizeof(sArg));

    ReplaceString(sArg, sizeof(sArg), "\"", "");
    ReplaceString(sArg, sizeof(sArg), "'", "");

    if (StrContains(sArg, "fake") != -1)
    {
        char sArray[2][32];
        ExplodeString(sArg, " ", sArray, 2, 32);

        for (int i = 0; i < StringToInt(sArray[1]); i++)
        {
            char sQuery[256];

            int iRandStyle = GetRandomInt(0, g_iStyles);
            int iRandTrack = GetRandomInt(0, 1);

            Format(sQuery, sizeof(sQuery),
            "INSERT INTO times(steamid64, map, style, track, time, date, jumps, sync, ssj) VALUES('%s', '%s', %i, %i, %f, %i, %i, %f, %f);",
            "5245", g_sMapName, iRandStyle, iRandTrack, GetRandomFloat(2.6, 10), GetTime(), GetRandomInt(0, 54), GetRandomFloat(70.0, 100.0), GetRandomFloat(600.0, 690.0));

            DB_Query(sQuery, "", DB_ErrorHandler);
        }
    }

    if (sArg[0] == '!')
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnPlayerJump(Event event, const char[] name, bool broadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    float fVel[3];

    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
    fVel[2] = 0.0;

    g_eInfo[client].fJumpSpeed = GetVectorLength(fVel);

    if (g_eCurFrame[client].iJumps >= 1 && !g_eInfo[client].bInRun)
    {
        return;
    }

    g_eCurFrame[client].iJumps++;

    if (g_eCurFrame[client].iJumps == 6)
    {
        g_eInfo[client].fSSJ = g_eInfo[client].fJumpSpeed;
    }
}

public void OnPlayerDeath(Event event, const char[] name, bool broadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if (g_eInfo[client].bInRun)
    {
        g_eInfo[client].bInRun = false;
    }
}

public void OnPlayerLeaveZone(int client, int tick, int track, int type)
{
    if (type == Zone_Start && track == g_eCurFrame[client].iTrack)
    {
        g_eInfo[client].iCurrentZone = -1;
        
        if (FindZone(track, Zone_End) == -1)
        {
            PrintToChat(client, "%s \x07No end zone for current track. Timer not starting.", g_sPrefix);
            return;
        }

        g_eInfo[client].bInRun       = true;
        g_eCurFrame[client].fTime    = 0.0;
        g_eCurFrame[client].fOffset  = CalculateTimeOffset(client, type);

        if (GetEntityFlags(client) & FL_ONGROUND)
        {
            /**
             * If they walked out of the start zone, reset jumps since it means they
             * didn't jump in the start zone at all.
             */
            g_eCurFrame[client].iJumps   = 0;
        }
    }
}

public void OnPlayerEnterZone(int client, int tick, int track, int type)
{
    if (track != g_eCurFrame[client].iTrack)
    {
        return;
    }

    g_eInfo[client].iCurrentZone = type;

    if (type == Zone_Start)
    {
        g_eInfo[client].bInRun       = false;
        g_eInfo[client].fSSJ         = 0.0;
        g_eInfo[client].iGoodChecks  = 0;
        g_eInfo[client].iTotalChecks = 0;
        g_eInfo[client].fPrevVel     = 0.0;
        g_eInfo[client].iFirstKey    = -1;
        
        g_eCurFrame[client].iJumps = 0;
    }

    if (type == Zone_End && g_eInfo[client].bInRun)
    {
        g_eCurFrame[client].fOffset  -= CalculateTimeOffset(client, type);

        if (g_eCurFrame[client].fOffset > 0.01 || g_eCurFrame[client].fOffset < -0.01)
        {
            /**
             * Bug: Offset will be really far negative (around 30 seconds) if the player enters the zone from the top or bottom due to
             * the way I find the angle between previous origins. It only finds the horizontal angle, so when the player enters
             * the zone from the top or bottom it points the tracerays horizontally, and since the player is above/below the zone the rays
             * never hit it, causing it to be around -30 (idk why that number but it seems to always be that).
             * My ghetto temp fix for this is just discarding the offset if its above or below one tick. (0.1 instead of 0.007 for 102 tick)
             */

            g_eCurFrame[client].fOffset = 0.0;
        }

        RunStats eStats;

        g_eCurFrame[client].fTime += g_eCurFrame[client].fOffset;
        g_eInfo[client].bInRun     = false;

        eStats.fTime     = g_eCurFrame[client].fTime;
        eStats.fDifPb    = eStats.fTime - g_fPb[client][g_eInfo[client].iStyle][track];
        eStats.fDifSr    = eStats.fTime - g_fSr[g_eInfo[client].iStyle][track];
        eStats.iTrack    = track;
        eStats.iStyle    = g_eInfo[client].iStyle;
        eStats.iJumps    = g_eCurFrame[client].iJumps;
        eStats.fSSJ      = g_eInfo[client].fSSJ;
        eStats.fSync     = g_eCurFrame[client].fSync;
        eStats.fMaxSpeed = g_eCurFrame[client].fMaxSpeed;
        eStats.fAvgSpeed = g_eInfo[client].fTotalSpeed / g_eInfo[client].fSpeedChecks;

        if (g_eCurFrame[client].fTime < g_fSr[g_eInfo[client].iStyle][track] || g_fSr[g_eInfo[client].iStyle][track] == 0.0)
        {
            Call_StartForward(g_hBeatSrForward);

            Call_PushCell(client);
            Call_PushCell(g_eInfo[client].iStyle);
            Call_PushCell(track);
            Call_PushFloat(g_eCurFrame[client].fTime);
            Call_PushFloat(g_fSr[g_eInfo[client].iStyle][track]);

            Call_Finish();

            g_fSr[g_eInfo[client].iStyle][track] = g_eCurFrame[client].fTime;
        }

        if (g_eCurFrame[client].fTime < g_fPb[client][g_eInfo[client].iStyle][track] || g_fPb[client][g_eInfo[client].iStyle][track] == 0.0) // Beats PB
        {
            Call_StartForward(g_hBeatPbForward);

            Call_PushCell(client);
            Call_PushArray(eStats, sizeof(RunStats));
            Call_PushFloat(g_fPb[client][g_eInfo[client].iStyle][track]);

            Call_Finish();

            g_fPb[client][g_eInfo[client].iStyle][track] = g_eCurFrame[client].fTime;

            /**
             * Save PB in database.
             */

            char sQuery_SQLite[256];

            Format(sQuery_SQLite, sizeof(sQuery_SQLite),
            "REPLACE INTO times VALUES((SELECT id FROM times WHERE map = '%s' AND style = %i AND track = %i AND steamid64 = '%s'), '%s', '%s', %i, %i, %f, %i, %i, %f, %f, %f, %f);",
            g_sMapName, eStats.iStyle, eStats.iTrack, g_eInfo[client].sId64, g_eInfo[client].sId64, g_sMapName, eStats.iStyle, eStats.iTrack, g_fPb[client][g_eInfo[client].iStyle][track], GetTime(), eStats.iJumps, eStats.fSync, eStats.fSSJ, eStats.fMaxSpeed, eStats.fAvgSpeed);

            DB_Query(sQuery_SQLite, "", DB_ErrorHandler, _);
        }
        else // Finishes map
        {
            Call_StartForward(g_hFinishTrackForward);

            Call_PushCell(client);
            Call_PushArray(eStats, sizeof(RunStats));
            Call_PushFloat(g_fPb[client][g_eInfo[client].iStyle][track]);

            Call_Finish();
        }
    }
}

public void OnClientSettingsChanged(int client)
{
    UpdatePlayerName(client);
}

public void OnPlayerTrackChange(int client, int track)
{
    g_eCurFrame[client].iTrack = track;
}

//=================================
// DB
//=================================

void SetupDB()
{
    char sType[16];

    /**
     * If there's no database entry in databases.cfg, use SQLite
     */

    if (!GetKV("globaltimer", "driver", sType, sizeof(sType), "configs/databases.cfg"))
    {
        g_eDB.iType = DB_Undefined;
    }
    else
    {
        /**
         * Otherwise, check what was specified.
         */

        if (StrEqual("mysql", sType))
        {
            g_eDB.iType = DB_MySQL;
        }
        else
        {
            g_eDB.iType = DB_SQLite;
        }
    }

    ConnectToDB();
}

void ConnectToDB()
{
    char sError[128];

    if (g_eDB.iType == DB_MySQL || g_eDB.iType == DB_SQLite)
    {
        g_eDB.db = SQL_Connect("globaltimer", true, sError, sizeof(sError));
    }
    else
    {
        Handle hKeyValues = CreateKeyValues("Connection");

        KvSetString(hKeyValues, "driver",   "sqlite");
        KvSetString(hKeyValues, "database", "globaltimer");

        g_eDB.db = SQL_ConnectCustom(hKeyValues, sError, sizeof(sError), true);

        CloseHandle(hKeyValues);

        g_eDB.iType = DB_SQLite;
    }

    if (g_eDB.db == null)
    {
        LogError("Error connecting to database. (%s)", sError);
        CloseHandle(g_eDB.db);

        g_eDB.bConnected = false; // just to make sure

        return;
    }

    g_eDB.bConnected = true;

    DB_Query("CREATE TABLE IF NOT EXISTS times(id INTEGER PRIMARY KEY, steamid64 TEXT, map TEXT, style INTEGER, track INTEGER, time REAL, date INTEGER, jumps INTEGER, sync REAL, ssj REAL, maxspeed REAL, avgspeed REAL);",
             "", DB_ErrorHandler, _);

    DB_Query("CREATE TABLE IF NOT EXISTS players(steamid64 TEXT PRIMARY KEY, name TEXT);",
             "", DB_ErrorHandler, _);
}

void DB_GetPbHandler(Database db, DBResultSet results, const char[] error, int client)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    /**
     * Copy database record from each track to g_fPb.
     */

    while (results.FetchRow())
    {
        g_fPb[client][results.FetchInt(3)][results.FetchInt(4)] = results.FetchFloat(5);

        Call_StartForward(g_hPbLoaded);

        Call_PushCell(client);
        Call_PushCell(results.FetchInt(3));
        Call_PushCell(results.FetchInt(4));
        Call_PushFloat(results.FetchFloat(5));

        Call_Finish();
    }
}

void DB_LoadTimesHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    PrintToServer("\nrows: %i (%i)", results.RowCount, GetTime());

    while (results.FetchRow())
    {
        char sNameQuery_SQLite[128];
        char sId64[18];

        results.FetchString(1, sId64, sizeof(sId64));

        int iStyle = results.FetchInt(3);
        int iTrack = results.FetchInt(4);

        /**
         * Load all times in database to arraylist for each style.
         */

        RunDBInfo eInfo;

        eInfo.iId    = results.FetchInt(0);
        eInfo.fTime  = results.FetchFloat(5);
        eInfo.iDate  = results.FetchInt(6);
        eInfo.iStyle = iStyle;
        eInfo.iTrack = iTrack;
        eInfo.iJumps = results.FetchInt(7);
        eInfo.fSync  = results.FetchFloat(8);
        eInfo.fSSJ   = results.FetchFloat(9);
        eInfo.fMaxSpeed = results.FetchFloat(10);
        eInfo.fAvgSpeed = results.FetchFloat(11);

        g_aTimes[iStyle][iTrack].PushArray(eInfo);

        PrintToServer("pushed time to %i, %i at %i", iStyle, iTrack, GetTime());

        if (g_fSr[iStyle][iTrack] == 0.0)
        {
            g_fSr[iStyle][iTrack] = eInfo.fTime;

            Call_StartForward(g_hSrLoaded);

            Call_PushFloat(eInfo.fTime);
            Call_PushArray(eInfo, sizeof(RunDBInfo));

            Call_Finish();
        }

        DataPack pack = new DataPack();

        pack.WriteCell(iStyle);
        pack.WriteCell(iTrack);

        Format(sNameQuery_SQLite, sizeof(sNameQuery_SQLite), "SELECT * FROM players WHERE steamid64 = '%s';", sId64);

        DB_Query(sNameQuery_SQLite, "", DB_LoadNamesHandler, pack);
    }
}

void DB_LoadNamesHandler(Database db, DBResultSet results, const char[] error, DataPack data)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    while (results.FetchRow())
    {
        data.Reset();
        
        int iStyle = data.ReadCell();
        int iTrack = data.ReadCell();

        char sName[MAX_NAME_LENGTH];

        results.FetchString(1, sName, sizeof(sName));

        g_aNames[iStyle][iTrack].PushString(sName);
    }
}

void DB_Query(const char[] sqlite, const char[] mysql, SQLQueryCallback callback, any data = 0, DBPriority priority = DBPrio_Normal)
{
    PrintToServer("DB_Query called (%s)", sqlite);

    if (g_eDB.iType == DB_MySQL)
    {
        g_eDB.db.Query(callback, mysql, data, priority);
    }
    else
    {
        g_eDB.db.Query(callback, sqlite, data, priority);
    }
}

//=================================
// Other
//=================================

void LoadTimes()
{
    PrintToServer("==================================\n\n\nLoadTimes called at %i\n\n\n=================================", GetTime());

    for (int style = 0; style < g_iStyles; style++)
    {
        for (int track = 0; track < 2; track++)
        {
            g_aTimes[style][track] = new ArrayList(sizeof(RunDBInfo));
            g_aNames[style][track] = new ArrayList(MAX_NAME_LENGTH);

            char sQuery_SQLite[128];

            Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM times WHERE map = '%s' AND track = %i AND style = %i ORDER BY time ASC;", g_sMapName, track, style);
            PrintToServer(sQuery_SQLite);

            DB_Query(sQuery_SQLite, "", DB_LoadTimesHandler);
        }
    }
}

void GetPlayerInfo(int client)
{
    UpdatePlayerName(client);

    GetClientAuthId(client, AuthId_SteamID64, g_eInfo[client].sId64, 18);

    /**
     * If OnMapStart hasn't been called yet, get the map name.
     */

    if (StrEqual(g_sMapName, ""))
    {
        GetCurrentMap(g_sMapName, sizeof(g_sMapName));
        GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));
    }

    char sQuery_SQLite[256];

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM times WHERE steamid64 = '%s' AND map = '%s';", g_eInfo[client].sId64, g_sMapName);

    DB_Query(sQuery_SQLite, "", DB_GetPbHandler, client);
}

void UpdatePlayerName(int client)
{
    if (StrEqual(g_eInfo[client].sId64, ""))
    {
        return;
    }

    char sQuery_SQLite[256];
    char sName[MAX_NAME_LENGTH];
    char sEscapedName[MAX_NAME_LENGTH * 2 + 1];

    GetClientName(client, sName, sizeof(sName));
    SQL_EscapeString(g_eDB.db, sName, sEscapedName, sizeof(sEscapedName));

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "REPLACE INTO players VALUES('%s', '%s');", g_eInfo[client].sId64, sEscapedName);

    DB_Query(sQuery_SQLite, "", DB_ErrorHandler, _);
}

float fLowestNum = 9999.0;

/**
 * Full credit for figuring this out goes to Momentum Mod. All I did was change their code to work with SourceMod.
 * https://github.com/momentum-mod/game
 */

float CalculateTimeOffset(int client, int type)
{
    float fVel[3];
    float fTemp[3];
    float fOffset;
    
    float fDif[3];
    float fDir[3];

    float fOBBMins[3];
    float fOBBMaxs[3];

    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
    
    GetEntPropVector(client, Prop_Send, "m_vecMins", fOBBMins);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", fOBBMaxs);

    for (int i = 0; i < 8; i++)
    {
        switch (i)
        {
            case 0:
            {
                AddVectors(g_fOrigins[client][0], fOBBMins, g_fTracePoint[client]);
            }
            case 1:
            {
                fTemp[0] = fOBBMins[0];
                fTemp[1] = fOBBMaxs[1];
                fTemp[2] = fOBBMins[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 2:
            {
                fTemp[0] = fOBBMins[0];
                fTemp[1] = fOBBMins[1];
                fTemp[2] = fOBBMaxs[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 3:
            {
                fTemp[0] = fOBBMins[0];
                fTemp[1] = fOBBMaxs[1];
                fTemp[2] = fOBBMaxs[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 4:
            {
                fTemp[0] = fOBBMaxs[0];
                fTemp[1] = fOBBMins[1];
                fTemp[2] = fOBBMaxs[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 5:
            {
                fTemp[0] = fOBBMaxs[0];
                fTemp[1] = fOBBMins[1];
                fTemp[2] = fOBBMins[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 6:
            {
                fTemp[0] = fOBBMaxs[0];
                fTemp[1] = fOBBMaxs[1];
                fTemp[2] = fOBBMins[2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint[client]);
            }
            case 7:
            {
                AddVectors(g_fOrigins[client][0], fOBBMaxs, g_fTracePoint[client]);
            }
        }

        if (type == Zone_Start)
        {
            SubtractVectors(g_fOrigins[client][0], g_fOrigins[client][1], fDif);
            NormalizeVector(fDif, fDif);

            GetVectorAngles(fDif, fDir);

            fDir[1] += 180.0;

            if (fDir[1] > 360.0)
            {
                fDir[1] -= 360.0;
            }

            TR_EnumerateEntities(g_fTracePoint[client], fDir, PARTITION_TRIGGER_EDICTS, RayType_Infinite, HitMask, client);
        }
        else
        {
            SubtractVectors(g_fOrigins[client][1], g_fOrigins[client][0], fDif);
            NormalizeVector(fDif, fDif);

            GetVectorAngles(fDif, fDir);

            fDir[1] += 180.0;

            if (fDir[1] > 360.0)
            {
                fDir[1] -= 360.0;
            }
            
            TR_EnumerateEntities(g_fTracePoint[client], fDir, PARTITION_TRIGGER_EDICTS, RayType_Infinite, HitMask, client);
        }
    }

    fVel[2] = 0.0;

    fOffset = fLowestNum / GetVectorLength(fVel);

    fLowestNum = 9999.0;

    return fOffset;
}

public bool HitMask(int entity, int client)
{
    char sTargetName[32];

    GetEntPropString(entity, Prop_Data, "m_iName", sTargetName, 32);

    if (StrContains(sTargetName, "gt_") == -1)
    {
        return true;
    }

    Handle hRay = TR_ClipCurrentRayToEntityEx(MASK_ALL, entity);

    float fPos[3];
    TR_GetEndPosition(fPos, hRay);

    delete hRay;

    float fDist = GetVectorDistance(g_fTracePoint[client], fPos);

    if (fDist < fLowestNum)
    {
        fLowestNum = fDist;
    }
    
    return false;
}

void LoadStyles()
{
    g_iStyles = 0;

    char sPath[128];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/globaltimer/styles.cfg");

    KeyValues kv = new KeyValues("Styles");
    kv.ImportFromFile(sPath);

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        return;
    }

    do
    {
        g_eStyles[g_iStyles].iIndex = g_iStyles;

        kv.GetString("name",     g_eStyles[g_iStyles].sName,     64);
        kv.GetString("shortcut", g_eStyles[g_iStyles].sShortcut, 16);

        g_eStyles[g_iStyles].iAllowForwards = kv.GetNum("allow_forwards", 1);
        g_eStyles[g_iStyles].iAllowLeft     = kv.GetNum("allow_left",     1);
        g_eStyles[g_iStyles].iAllowRight    = kv.GetNum("allow_right",    1);
        g_eStyles[g_iStyles].iAllowBack     = kv.GetNum("allow_back",     1);
        
        g_eStyles[g_iStyles].bAllowPrespeed = view_as<bool>(kv.GetNum("allow_prespeed", 0));
        g_eStyles[g_iStyles].bAutohop       = view_as<bool>(kv.GetNum("autohop",        1));
        g_eStyles[g_iStyles].iCustom        = kv.GetNum("custom", 0);

        g_iStyles++;
    }
    while (kv.GotoNextKey());

    delete kv;
}

void CalculateSync(int client, float vel, float angles[3])
{
    if (FloatAbs(angles[1] - g_fPrevAngles[client][1]) > 0.0)
    {
        if (FloatAbs(vel - g_eInfo[client].fPrevVel) > 0.0)
        {
            g_eInfo[client].iGoodChecks++;
        }

        g_eInfo[client].iTotalChecks++;
    }

    g_eInfo[client].fPrevVel = vel;
    g_fPrevAngles[client] = angles;
}

int GetPlacementByTimeLocal(float time, int style, int track)
{
    if (g_aTimes[style][track].Length == 0 || time < g_fSr[style][track] && time != 0.0)
    {
        return 1;
    }

    if (time == 0.0)
    {
        return 0;
    }

    for (int i = 0; i < g_aTimes[style][track].Length; i++)
    {
        RunDBInfo info;

        g_aTimes[style][track].GetArray(i, info);

        if (time < info.fTime)
        {
            return ++i;
        }
    }

    return g_aTimes[style][track].Length + 1;
}

int GetTotalTimesLocal(int style, int track)
{
    if (g_aTimes[style][track] == null)
    {
        return -1;
    }

    return g_aTimes[style][track].Length + 1;
}

//=================================
// Menus
//=================================

int MenuHandler_Styles(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        g_eInfo[client].iStyle     = index;
        g_eCurFrame[client].iStyle = index;
        g_eInfo[client].iFirstKey  = -1;

        CS_SetClientClanTag(client, g_eStyles[index].sShortcut);

        Call_StartForward(g_hStyleChangeForward);

        Call_PushCell(client);
        Call_PushArray(g_eStyles[g_eInfo[client].iStyle], sizeof(Style));

        Call_Finish();

        ForceRestartPlayer(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_RecordsParent(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[2];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        OpenRecordsMenu_Styles(client, StringToInt(sInfo));
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

int MenuHandler_RecordsStyles(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sShortcut[6];

        if (!menu.GetItem(index, sShortcut, sizeof(sShortcut)))
        {
            return 0;
        }

        char sStrings[6][2];

        ExplodeString(sShortcut, "-", sStrings, 2, 6);

        OpenRecordsMenu_Times(client, StringToInt(sStrings[0]), StringToInt(sStrings[1]));
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        OpenRecordsMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_Times(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[12];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        char sStrings[3][2];
        int iIndex, iStyle, iTrack;

        ExplodeString(sInfo, "-", sStrings, 3, 2);

        iIndex = StringToInt(sStrings[0]);
        iStyle = StringToInt(sStrings[1]);
        iTrack = StringToInt(sStrings[2]);

        DisplayRunInfo(client, iIndex, iStyle, iTrack);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        OpenRecordsMenu_Styles(client, Track_Main);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_ViewTime(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        OpenRecordsMenu_Styles(client, Track_Main);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void OpenStyleMenu(int client)
{
    Menu hMenu = new Menu(MenuHandler_Styles);

    hMenu.SetTitle("Styles");

    for (int i = 0; i < g_iStyles; i++)
    {
        if (g_eInfo[client].iStyle == i)
        {
            hMenu.AddItem(g_eStyles[i].sShortcut, g_eStyles[i].sName, ITEMDRAW_DISABLED);
        }
        else
        {
            hMenu.AddItem(g_eStyles[i].sShortcut, g_eStyles[i].sName);
        }
    }

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenRecordsMenu(int client)
{
    Menu mMenu = new Menu(MenuHandler_RecordsParent);

    mMenu.SetTitle("Select a track:");

    mMenu.AddItem("0", "Main");
    mMenu.AddItem("1", "Bonus");

    mMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenRecordsMenu_Styles(int client, int track)
{
    Menu mMenu = new Menu(MenuHandler_RecordsStyles);

    mMenu.SetTitle("Select a style:");

    for (int i = 0; i < g_iStyles; i++)
    {
        char sStyle[32];
        char sShortcut[6];
        char sTime[12];
        
        if (g_fSr[i][track] == 0.0)
        {
            Format(sStyle, sizeof(sStyle), "%s", g_eStyles[i].sName);
            mMenu.AddItem("invalid", sStyle, ITEMDRAW_DISABLED);
        }
        else
        {
            FormatSeconds(g_fSr[i][track], sTime, sizeof(sTime), Accuracy_Med, false, true);

            Format(sStyle, sizeof(sStyle), "%s - %s", g_eStyles[i].sName, sTime);
            Format(sShortcut, sizeof(sShortcut), "%i-%i", i, track);

            mMenu.AddItem(sShortcut, sStyle);
        }
    }

    mMenu.ExitBackButton = true;

    mMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenRecordsMenu_Times(int client, int style, int track)
{
    Menu mMenu = new Menu(MenuHandler_Times);

    mMenu.SetTitle("Displaying times for '%s'\nStyle: %s\nTrack: %s", g_sMapName, g_eStyles[style].sName, g_sTracks[track]);

    RunDBInfo info;

    char sRecord[64];
    char sShortcut[12];

    char sTime[18];
    char sName[MAX_NAME_LENGTH];

    for (int i = 0; i < g_aTimes[style][track].Length; i++)
    {
        g_aTimes[style][track].GetArray(i, info);
        g_aNames[style][track].GetString(i, sName, sizeof(sName));

        FormatSeconds(info.fTime, sTime, sizeof(sTime), Accuracy_High, false, false);

        Format(sRecord, sizeof(sRecord), "[#%i] %s - %s", i + 1, sName, sTime);
        Format(sShortcut, sizeof(sShortcut), "%i-%i-%i", i, style, track);

        mMenu.AddItem(sShortcut, sRecord);
    }

    mMenu.ExitBackButton = true;

    mMenu.Display(client, MENU_TIME_FOREVER);
}

void DisplayRunInfo(int client, int index, int style, int track)
{
    RunDBInfo eInfo;
    char sName[MAX_NAME_LENGTH];
    char sTime[18];
    char sDate[32];

    char sStat[64];

    g_aTimes[style][track].GetArray(index, eInfo);
    g_aNames[style][track].GetString(index, sName, sizeof(sName));

    FormatSeconds(eInfo.fTime, sTime, sizeof(sTime), Accuracy_High, false, false);
    FormatTime(sDate, sizeof(sDate), "%c", eInfo.iDate);

    Menu mMenu = new Menu(MenuHandler_ViewTime);    

    mMenu.SetTitle(
        "------------------------------\n\
        Runner: %s\n\
        Style: %s\n\
        Track: %s\n\
        Date: %s\n\
        Map: %s\n\
        ------------------------------",
        sName, g_eStyles[eInfo.iStyle].sName, g_sTracks[eInfo.iTrack], sDate, g_sMapName);

    Format(sStat, sizeof(sStat), "Time: %s\n ", sTime);
    mMenu.AddItem("time", sStat, ITEMDRAW_DISABLED);

    Format(sStat, sizeof(sStat), "Sync: %.1f%%", eInfo.fSync);
    mMenu.AddItem("sync", sStat, ITEMDRAW_DISABLED);

    Format(sStat, sizeof(sStat), "Jumps: %i", eInfo.iJumps);
    mMenu.AddItem("jumps", sStat, ITEMDRAW_DISABLED);

    Format(sStat, sizeof(sStat), "SSJ: %.2f u/s\n ", eInfo.fSSJ);
    mMenu.AddItem("ssj", sStat, ITEMDRAW_DISABLED);

    Format(sStat, sizeof(sStat), "Avg Speed: %.1f u/s", eInfo.fAvgSpeed);
    mMenu.AddItem("avgspeed", sStat, ITEMDRAW_DISABLED);

    Format(sStat, sizeof(sStat), "Max Speed: %.1f u/s", eInfo.fMaxSpeed);
    mMenu.AddItem("maxspeed", sStat, ITEMDRAW_DISABLED);

    mMenu.ExitBackButton = true;

    mMenu.Display(client, MENU_TIME_FOREVER);
}

//=================================
// Commands
//=================================

public Action CMD_Style(int client, int args)
{
    OpenStyleMenu(client);

    return Plugin_Handled;
}

public Action CMD_Top(int client, int args)
{
    OpenRecordsMenu(client);

    return Plugin_Handled;
}

//=================================
// Natives
//=================================

public int Native_GetPlayerFrame(Handle plugin, int param)
{
    SetNativeArray(2, g_eCurFrame[GetNativeCell(1)], sizeof(RunFrame));
}

public int Native_GetPlayerStyleSettings(Handle plugin, int param)
{
    SetNativeArray(2, g_eStyles[g_eInfo[GetNativeCell(1)].iStyle], sizeof(Style));
}

public int Native_GetPlayerTrack(Handle plugin, int param)
{
    return g_eCurFrame[GetNativeCell(1)].iTrack;
}

public int Native_StopTimer(Handle plugin, int param)
{
    if (!g_eInfo[GetNativeCell(1)].bInRun)
    {
        return;
    }

    if (view_as<bool>(GetNativeCell(2)))
    {
        PrintToChat(GetNativeCell(1), "%s \x07Your timer has been stopped.", g_sPrefix);
    }

    g_eInfo[GetNativeCell(1)].bInRun = false;
}

public int Native_IsPlayerInRun(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].bInRun;
}

public int Native_GetPlayerJumpSpeed(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].fJumpSpeed;
}

public int Native_GetPlayerPb(Handle plugin, int param)
{
    return view_as<int>(g_fPb[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_GetSr(Handle plugin, int param)
{
    return view_as<int>(g_fSr[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetPlayerCurrentZone(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iCurrentZone;
}

public int Native_GetPlacementByTime(Handle plugin, int param)
{
    return GetPlacementByTimeLocal(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3));
}

public int Native_GetTotalTimes(Handle plugin, int param)
{
    return GetTotalTimesLocal(GetNativeCell(1), GetNativeCell(2));
}
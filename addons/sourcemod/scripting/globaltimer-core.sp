#include <globaltimer>

#include <sdkhooks>
#include <sdktools>
#include <sourcemod>

enum struct PlayerInfo
{
    bool  bInRun;       // Whether the player's timer should be running.
    int   iStartTick;   // The tick the player's timer started at.
    int   iTrack;       // Current track of player. (Main/Bonus)
    char  sId64[18];    // SteamID64 of player.
    float fOffset;      // Time missed between ticks.
    int   iJumps;       // Amount of jumps in a run.
    float iJumpSpeed;   // Speed from previous jump.
    int   iCurrentZone; // Whether the player's in a zone or not. (-1 = no zone, >0 = zone index)
}

PlayerInfo g_eInfo[MAXPLAYERS + 1];
DB         g_eDB;

float g_fPb[MAXPLAYERS + 1][2]; // Player's pb for main and bonus tracks.
float g_fSr[2];                 // Server record for main and bonus tracks.

float g_fOBBMins[MAXPLAYERS + 1][3];
float g_fOBBMaxs[MAXPLAYERS + 1][3];
float g_fOrigins[MAXPLAYERS + 1][2][3];
float g_fTracePoint[3];

int g_iTimes[2]; // Total amount of times for each style.

bool g_bLate;

char g_sMapName[128];

Handle g_hBeatSrForward;
Handle g_hBeatPbForward;
Handle g_hFinishTrackForward;

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

    g_hBeatSrForward      = CreateGlobalForward("OnPlayerBeatSr",        ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hBeatPbForward      = CreateGlobalForward("OnPlayerBeatPb",        ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
    g_hFinishTrackForward = CreateGlobalForward("OnPlayerFinishedTrack", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);

    HookEvent("player_jump", OnPlayerJump);

    AddCommandListener(OnPlayerNoclip, "noclip");

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

    CreateNative("GetPlayerCurrentZone", Native_GetPlayerCurrentZone);
    CreateNative("GetPlayerJumpCount",   Native_GetPlayerJumpCount);
    CreateNative("GetPlayerJumpSpeed",   Native_GetPlayerJumpSpeed);
    CreateNative("GetPlayerPb",          Native_GetPlayerPb);
    CreateNative("GetPlayerTime",        Native_GetPlayerTime);
    CreateNative("GetPlayerTrack",       Native_GetPlayerTrack);
    CreateNative("IsPlayerInRun",        Native_IsPlayerInRun);
    CreateNative("StopTimer",            Native_StopTimer);
    CreateNative("GetSr",                Native_GetSr);

    RegPluginLibrary("globaltimer-core");
    
    return APLRes_Success;
}

//=================================
// Forwards
//=================================

public void OnMapStart()
{
    g_fSr[Track_Main]  = 0.0;
    g_fSr[Track_Bonus] = 0.0;

    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));

    DB_GetSr(Track_Main);
    DB_GetSr(Track_Bonus);
}

public void OnClientPostAdminCheck(int client)
{
    g_eInfo[client].bInRun     = false;
    g_eInfo[client].iStartTick = -1;
    g_eInfo[client].iTrack     = Track_Main;
    g_eInfo[client].fOffset    = 0.0;
    g_fPb[client][0]           = 0.0;
    g_fPb[client][1]           = 0.0;

    GetPlayerInfo(client);
    
    SDKHook(client, SDKHook_PostThinkPost, OnPostThink);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnPostThink(int client)
{
    g_fOrigins[client][1] = g_fOrigins[client][0];
    GetClientAbsOrigin(client, g_fOrigins[client][0]);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    return Plugin_Handled;
}

public void OnPlayerJump(Event event, const char[] name, bool broadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    float fVel[3];

    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
    fVel[2] = 0.0;

    g_eInfo[client].iJumpSpeed = GetVectorLength(fVel);

    if (g_eInfo[client].iJumps >= 1 && !g_eInfo[client].bInRun)
    {
        return;
    }

    g_eInfo[client].iJumps++;
}

public void OnPlayerLeaveZone(int client, int tick, int track, int type)
{
    if (type == Zone_Start && track == g_eInfo[client].iTrack)
    {
        g_eInfo[client].bInRun       = true;
        g_eInfo[client].iStartTick   = tick;
        g_eInfo[client].fOffset      = CalculateTimeOffset(client, type);
        g_eInfo[client].iCurrentZone = -1;
    }
}

public void OnPlayerEnterZone(int client, int tick, int track, int type)
{
    if (track != g_eInfo[client].iTrack)
    {
        return;
    }

    g_eInfo[client].iCurrentZone = type;

    if (type == Zone_Start)
    {
        g_eInfo[client].bInRun = false;
        g_eInfo[client].iJumps = 0;
    }

    if (type == Zone_End && g_eInfo[client].bInRun)
    {
        g_eInfo[client].fOffset -= CalculateTimeOffset(client, type);

        float fTime = ((tick - g_eInfo[client].iStartTick) * GetTickInterval()) + g_eInfo[client].fOffset;

        g_eInfo[client].bInRun = false;

        if (fTime < g_fSr[track] || g_fSr[track] == 0.0)
        {
            Call_StartForward(g_hBeatSrForward);

            Call_PushCell(client);
            Call_PushCell(track);
            Call_PushFloat(fTime);
            Call_PushFloat(g_fSr[track]);

            Call_Finish();

            g_fSr[track] = fTime;
        }

        if (fTime < g_fPb[client][track] || g_fPb[client][track] == 0.0) // Beats PB
        {
            Call_StartForward(g_hBeatPbForward);

            Call_PushCell(client);
            Call_PushCell(track);
            Call_PushFloat(fTime);
            Call_PushFloat(g_fPb[client][track]);

            Call_Finish();

            g_fPb[client][track] = fTime;

            /**
             * Save PB in database.
             */

            char sQuery_SQLite[256];

            Format(sQuery_SQLite, sizeof(sQuery_SQLite),
            "REPLACE INTO records VALUES((SELECT id FROM records WHERE map = '%s' AND track = %i AND steamid64='%s'), '%s', '%s', %i, %f);",
            g_sMapName, track, g_eInfo[client].sId64, g_eInfo[client].sId64, g_sMapName, track, g_fPb[client][track]);

            DB_Query(sQuery_SQLite, "", DB_ErrorHandler, _);
        }
        else // Finishes map
        {
            Call_StartForward(g_hFinishTrackForward);

            Call_PushCell(client);
            Call_PushCell(track);
            Call_PushFloat(fTime);
            Call_PushFloat(g_fPb[client][track]);

            Call_Finish();
        }
    }
}

public void OnPlayerTrackChange(int client, int track)
{
    g_eInfo[client].iTrack = track;
}

public Action OnPlayerNoclip(int client, const char[] command, int args)
{
    if (g_eInfo[client].bInRun)
    {
        StopTimer(client, true);
    }

    return Plugin_Continue;
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

    DB_Query("CREATE TABLE IF NOT EXISTS records(id INTEGER PRIMARY KEY, steamid64 TEXT, map TEXT, track INTEGER, time REAL);",
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
        g_fPb[client][results.FetchInt(3)] = results.FetchFloat(4);
    }
}

void DB_GetSrHandler(Database db, DBResultSet results, const char[] error, int track)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    while (results.FetchRow())
    {
        g_fSr[track] = results.FetchFloat(4);
        PrintToChatAll("SR for track %i: %f", track, results.FetchFloat(4));
    }
}

void DB_GetSr(int track)
{
    char sQuery_SQLite[128];

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM 'records' WHERE map='%s' AND track = %i ORDER BY time ASC LIMIT 1", g_sMapName, track);
    
    DB_Query(sQuery_SQLite, "", DB_GetSrHandler, track);
}

void DB_Query(const char[] sqlite, const char[] mysql, SQLQueryCallback callback, any data = 0, DBPriority priority = DBPrio_Normal)
{
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

void GetPlayerInfo(int client)
{
    GetClientAuthId(client, AuthId_SteamID64, g_eInfo[client].sId64, 18);

    GetEntPropVector(client, Prop_Send, "m_vecMins", g_fOBBMins[client]);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", g_fOBBMaxs[client]);

    /**
     * If OnMapStart hasn't been called yet, get the map name.
     */

    if (StrEqual(g_sMapName, ""))
    {
        GetCurrentMap(g_sMapName, sizeof(g_sMapName));
        GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));
    }

    char sQuery_SQLite[256];

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM records WHERE steamid64 = '%s' AND map = '%s';", g_eInfo[client].sId64, g_sMapName);

    DB_Query(sQuery_SQLite, "", DB_GetPbHandler, client);
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

    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);

    for (int i = 0; i < 8; i++)
    {
        switch (i)
        {
            case 0:
            {
                AddVectors(g_fOrigins[client][0], g_fOBBMins[client], g_fTracePoint);
            }
            case 1:
            {
                fTemp[0] = g_fOBBMins[client][0];
                fTemp[1] = g_fOBBMaxs[client][1];
                fTemp[2] = g_fOBBMins[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 2:
            {
                fTemp[0] = g_fOBBMins[client][0];
                fTemp[1] = g_fOBBMins[client][1];
                fTemp[2] = g_fOBBMaxs[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 3:
            {
                fTemp[0] = g_fOBBMins[client][0];
                fTemp[1] = g_fOBBMaxs[client][1];
                fTemp[2] = g_fOBBMaxs[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 4:
            {
                fTemp[0] = g_fOBBMaxs[client][0];
                fTemp[1] = g_fOBBMins[client][1];
                fTemp[2] = g_fOBBMaxs[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 5:
            {
                fTemp[0] = g_fOBBMaxs[client][0];
                fTemp[1] = g_fOBBMins[client][1];
                fTemp[2] = g_fOBBMins[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 6:
            {
                fTemp[0] = g_fOBBMaxs[client][0];
                fTemp[1] = g_fOBBMaxs[client][1];
                fTemp[2] = g_fOBBMins[client][2];
                AddVectors(g_fOrigins[client][0], fTemp, g_fTracePoint);
            }
            case 7:
            {
                AddVectors(g_fOrigins[client][0], g_fOBBMaxs[client], g_fTracePoint);
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

            TR_EnumerateEntities(g_fTracePoint, fDir, PARTITION_TRIGGER_EDICTS, RayType_Infinite, HitMask);
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

            TR_EnumerateEntities(g_fTracePoint, fDir, PARTITION_TRIGGER_EDICTS, RayType_Infinite, HitMask);
        }
    }

    fOffset = fLowestNum / GetVectorLength(fVel);

    fLowestNum = 9999.0;

    return fOffset;
}

public bool HitMask(int entity)
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

    float fDist = GetVectorDistance(g_fTracePoint, fPos);

    if (fDist < fLowestNum)
    {
        fLowestNum = fDist;
    }
    
    return false;
}

//=================================
// Natives
//=================================

public int Native_GetPlayerTrack(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iTrack;
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

public int Native_GetPlayerTime(Handle plugin, int param)
{
    int client = GetNativeCell(1);

    if (g_eInfo[client].bInRun)
    {
        return ((GetGameTickCount() - g_eInfo[client].iStartTick) * GetTickInterval());
    }
    else
    {
        return -1.0;
    }
}

public int Native_IsPlayerInRun(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].bInRun;
}

public int Native_GetPlayerPb(Handle plugin, int param)
{
    return g_fPb[GetNativeCell(1)][GetNativeCell(2)];
}

public int Native_GetSr(Handle plugin, int param)
{
    return g_fSr[GetNativeCell(1)];
}

public int Native_GetPlayerJumpCount(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iJumps;
}

public int Native_GetPlayerJumpSpeed(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iJumpSpeed;
}

public int Native_GetPlayerCurrentZone(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iCurrentZone;
}
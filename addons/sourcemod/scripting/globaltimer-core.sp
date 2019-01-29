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

Menu g_mSrMenu;

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

    RegConsoleCmd("sm_top", CMD_Top, "Displays top times for the map.");

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

    CreateNative("GetPlayerTrack", Native_GetPlayerTrack);

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

    SetupSrMenu();
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
}

public void OnPostThink(int client)
{
    g_fOrigins[client][1] = g_fOrigins[client][0];
    GetClientAbsOrigin(client, g_fOrigins[client][0]);
}

public void OnPlayerLeaveZone(int client, int tick, int track, int type)
{
    if (type == Zone_Start && track == g_eInfo[client].iTrack)
    {
        g_eInfo[client].bInRun     = true;
        g_eInfo[client].iStartTick = tick;
        g_eInfo[client].fOffset    = CalculateTimeOffset(client, type);
    }
}

public void OnPlayerEnterZone(int client, int tick, int track, int type)
{
    if (type == Zone_End && track == g_eInfo[client].iTrack && g_eInfo[client].bInRun)
    {
        g_eInfo[client].fOffset -= CalculateTimeOffset(client, type);

        char sTime[32];
        float fTime = ((tick - g_eInfo[client].iStartTick) * GetTickInterval()) + g_eInfo[client].fOffset;

        FormatSeconds(fTime, sTime, sizeof(sTime), true);
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

//=================================
// Natives
//=================================

public int Native_GetPlayerTrack(Handle plugin, int param)
{
    return g_eInfo[GetNativeCell(1)].iTrack;
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

    char sShortCut[3];
    char sText[64];
    char sTime[16];
    char sHolder[64];

    if (g_iTimes[track] == 0)
    {
        g_fSr[track] = results.FetchFloat(4);
    }

    while (results.FetchRow())
    {
        g_iTimes[track]++;

        results.FetchString(1, sHolder, sizeof(sHolder));
        
        FormatSeconds(results.FetchFloat(4), sTime, sizeof(sTime), true);

        Format(sShortCut, sizeof(sShortCut), "%i", g_iTimes[track]);
        Format(sText, sizeof(sText), "[#%i] - %s (%s)", g_iTimes[track], sTime, sHolder);

        g_mSrMenu.AddItem(sShortCut, sText);
    }
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
// Menus
//=================================

int MenuHandler_Sr(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
    }

    return 0;
}

void SetupSrMenu()
{
    /**
     * Just kinda thrown in without much thought for now. Will
     * improve later
     */
    
    g_mSrMenu = new Menu(MenuHandler_Sr);

    g_mSrMenu.SetTitle("Records");

    g_mSrMenu.Pagination = true;

    char sQuery_SQLite[128];

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM 'records' WHERE map='%s' AND track = 0 ORDER BY time ASC", g_sMapName);
    
    DB_Query(sQuery_SQLite, "", DB_GetSrHandler, 0);
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
// Commands
//=================================

public Action CMD_Top(int client, int args)
{
    g_mSrMenu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}
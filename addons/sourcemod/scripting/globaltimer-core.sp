#include <globaltimer>

#include <sourcemod>

enum struct PlayerInfo
{
    bool  bInRun;       // Whether the player's timer should be running.
    int   iStartTick;   // The tick the player's timer started at.
    int   iTrack;       // Current track of player. (Main/Bonus)
    char  sId64[18];    // SteamID64 of player.
}

PlayerInfo g_eInfo[MAXPLAYERS + 1];
DB         g_eDB;

float g_fPb[MAXPLAYERS + 1][2]; // Player's pb for main and bonus tracks.
float g_fSr[2];                 // Server record for main and bonus tracks.

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

    // g_hBeatSrForward      = CreateGlobalForward("OnPlayerBeatSr", ET_Event, Param_Cell, Param_Cell, Param_Float, Param_Float);
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
    
    return APLRes_Success;
}

//=================================
// Forwards
//=================================

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));

    SetupSrMenu();
}

public void OnClientConnected(int client)
{
    g_eInfo[client].bInRun     = false;
    g_eInfo[client].iStartTick = -1;
    g_eInfo[client].iTrack     = Track_Main;
    g_fPb[client][0]           = 0.0;
    g_fPb[client][1]           = 0.0;
}

public void OnClientPostAdminCheck(int client)
{
    GetPlayerInfo(client);
}

public void OnPlayerLeaveZone(int client, int tick, int track, int type)
{
    if (type == Zone_Start && track == g_eInfo[client].iTrack)
    {
        g_eInfo[client].bInRun     = true;
        g_eInfo[client].iStartTick = tick;
        PrintToChatAll("wr: %f", g_fSr[track]);
    }
}

public void OnPlayerEnterZone(int client, int tick, int track, int type)
{
    if (type == Zone_End && track == g_eInfo[client].iTrack && g_eInfo[client].bInRun)
    {
        char sTime[32];
        float fTime = (tick - g_eInfo[client].iStartTick) * GetTickInterval();

        FormatSeconds(fTime, sTime, sizeof(sTime), true);
        g_eInfo[client].bInRun = false;

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

            DB_Query(sQuery_SQLite, "", DB_SavePbHandler, _);
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

void DB_SavePbHandler(Database db, DBResultSet results, const char[] error, int client)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }
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

void DB_GetSrHandler(Database db, DBResultSet results, const char[] error, any data)
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

    while (results.FetchRow())
    {
        g_iTimes[0]++;

        results.FetchString(1, sHolder, sizeof(sHolder));
        
        FormatSeconds(results.FetchFloat(4), sTime, sizeof(sTime), true);

        Format(sShortCut, sizeof(sShortCut), "%i", g_iTimes[0]);
        Format(sText, sizeof(sText), "[#%i] - %s (%s)", g_iTimes[0], sTime, sHolder);

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
        PrintToChatAll("TeasSs");
    }

    return 0;
}

void SetupSrMenu()
{
    g_mSrMenu = new Menu(MenuHandler_Sr);

    g_mSrMenu.SetTitle("Records");

    g_mSrMenu.Pagination = true;

    char sQuery_SQLite[128];

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM 'records' WHERE map='%s' AND track = 0 ORDER BY time ASC", g_sMapName);
    
    DB_Query(sQuery_SQLite, "", DB_GetSrHandler, _);
}

//=================================
// Other
//=================================

void GetPlayerInfo(int client)
{
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

    Format(sQuery_SQLite, sizeof(sQuery_SQLite), "SELECT * FROM records WHERE steamid64 = '%s' AND map = '%s';", g_eInfo[client].sId64, g_sMapName);

    DB_Query(sQuery_SQLite, "", DB_GetPbHandler, client);
}

//=================================
// Commands
//=================================

public Action CMD_Top(int client, int args)
{
    g_mSrMenu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}
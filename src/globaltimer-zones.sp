#include <globaltimer>

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#define DEFAULT_ZONE_HEIGHT   140
#define DEFAULT_GRID_SIZE     64
#define TIMER_ZONE_UPDATERATE 1.0
#define MAXZONES              4

enum struct PlayerZoneInfo
{
    bool   bIsCreatingZone;    // If the player is in the creating zone menu.
    int    iInZone;            // Index of the zone the player is in (-1 if not in one).
    int    iCurrentTrack;      // Index of current track (see enum in include file).
    int    iEditingTrack;      // Chosen track to be edited in create zone menu (^).
    Handle hZoneTimer;         // Timer for drawing zones.
    Handle hSnapTimer;         // Timer for updating snap pos.
}

PlayerZoneInfo g_pInfo[MAXPLAYERS + 1];

float  g_fSpawnPoint[MAXPLAYERS + 1][2][3];
float  g_fSpawnAngles[MAXPLAYERS + 1][2][3];

float  g_fZonePoints[MAXZONES][8][3];
float  g_fOrigin[MAXPLAYERS + 1][3];
float  g_fSnapPoint[MAXPLAYERS + 1][3];
float  g_fSelectedPoints[MAXPLAYERS + 1][2][3];

bool   g_bLate;
bool   g_bIsZoneValid[MAXZONES];
bool   g_bHasCustomSpawn[MAXPLAYERS + 1][2];

int    g_iBeam;
int    g_iSnapSize = DEFAULT_GRID_SIZE;
int    g_iTrigger[MAXZONES];

char   g_sMapName[128];

Handle g_hZoneLeaveForward;
Handle g_hZoneEnterForward;
Handle g_hPlayerTrackChangeForward;

Database g_hDB;
bool     g_bDBLoaded;

char g_sTrackNames[][] =
{
    "Main (Start)",
    "Main (End)",
    "Bonus (Start)",
    "Bonus (End)"
};

int g_iTrackColors[][] =
{
    {   0, 255, 255, 255 }, // Main  (Start)
    { 255, 255, 255, 255 }, // Main  (End)
    {   0, 255, 255, 255 }, // Bonus (Start)
    { 255, 255, 255, 255 }  // Bonus (End)
};

public Plugin myinfo =
{
    name = "[GlobalTimer] Zones",
    author = AUTHOR,
    description = "Zones for timer.",
    version = VERSION,
    url = URL
};

public void OnPluginStart()
{
    g_bDBLoaded = false;

    g_hZoneLeaveForward         = CreateGlobalForward("OnPlayerLeaveZone",   ET_Event, Param_Cell, Param_Cell, Param_Cell);
    g_hZoneEnterForward         = CreateGlobalForward("OnPlayerEnterZone",   ET_Event, Param_Cell, Param_Cell, Param_Cell);
    g_hPlayerTrackChangeForward = CreateGlobalForward("OnPlayerTrackChange", ET_Event, Param_Cell);

    // Admin commands
    RegAdminCmd("sm_zone", CMD_Zone, ADMFLAG_GENERIC, "Opens zone menu.");

    // Player commands
    RegConsoleCmd("sm_reset",    CMD_Reset,    "Restarts players timer.");
    RegConsoleCmd("sm_bonus",    CMD_Bonus,    "Teleports player to bonus.");
    RegConsoleCmd("sm_main",     CMD_Main,     "Teleports player to main track.");
    RegConsoleCmd("sm_end",      CMD_End,      "Teleports player to end of current track.");
    RegConsoleCmd("sm_setspawn", CMD_SetSpawn, "Sets players spawnpoint.");
    RegConsoleCmd("sm_delspawn", CMD_DelSpawn, "Deletes set spawnpoint.");

    // Aliases
    RegConsoleCmd("sm_r",     CMD_Reset, "Restarts players timer.");
    RegConsoleCmd("sm_b",     CMD_Bonus, "Teleports player to bonus.");
    RegConsoleCmd("sm_s",     CMD_Main,  "Teleports player to main track.");
    RegConsoleCmd("sm_m",     CMD_Main,  "Teleports player to main track.");

    HookEvent("round_start", OnRoundStart);

    SetupDB();

    if (g_bLate)
    {
        for (int i = 1; i < MAXPLAYERS; i++)
        {
            if (IsClientConnected(i))
            {
                OnClientConnected(i);
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    g_bLate = late;

    CreateNative("IsPlayerInZone", Native_IsPlayerInZone);
    CreateNative("GetPlayerTrack", Native_GetPlayerTrack);

    RegPluginLibrary("globaltimer_zones");

    return APLRes_Success;
}

//=================================
// Forwards
//=================================

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    GetClientAbsOrigin(client, g_fOrigin[client]);

    HandleZoneMovement(client);
}

public void OnClientConnected(int client)
{
    /*
     * Start the timer for drawing zones when a client connects,
     * since it should be constantly running.
    */
    g_pInfo[client].hZoneTimer = CreateTimer(TIMER_ZONE_UPDATERATE, DrawZoneLoop, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    ClearPlayerInfo(client);
}

public Action OnRoundStart(Event event, const char[] name, bool broadcast)
{
    /**
     * Loop through all valid zones and create trigger entity for them.
    */
    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_bIsZoneValid[i])
        {
            CreateTrigger(i);
        }
    }
}

public void OnMapStart()
{
    /**
     * Get map name (ex: "bhop_<name>").
    */
    char sMapNameTemp[128];
    GetCurrentMap(sMapNameTemp, sizeof(sMapNameTemp));

    GetMapDisplayName(sMapNameTemp, g_sMapName, sizeof(g_sMapName));

    g_iBeam = PrecacheModel("materials/sprites/purplelaser1.vmt", true);
    PrecacheModel("models/props/cs_office/vending_machine.mdl", true);

    LoadZones();
}

public void OnStartTouch(int entity, int other)
{
    for (int i = 0; i < MAXZONES; i++)
    {
        if (entity == g_iTrigger[i])
        {
            Call_StartForward(g_hZoneEnterForward);

            Call_PushCell(other);
            Call_PushCell(GetGameTickCount());
            Call_PushCell(i);

            Call_Finish();

            if (IsValidClient(other))
            {
                g_pInfo[other].iInZone = i;
            }

            break;
        }
    }
}

public void OnEndTouch(int entity, int other)
{
    for (int i = 0; i < MAXZONES; i++)
    {
        if (entity == g_iTrigger[i])
        {
            Call_StartForward(g_hZoneLeaveForward);

            Call_PushCell(other);
            Call_PushCell(GetGameTickCount());
            Call_PushCell(i);

            Call_Finish();

            if (IsValidClient(other))
            {
                g_pInfo[other].iInZone = -1;
            }

            break;
        }
    }
}

// Just for testing stuff without making another plugin
public void OnPlayerBeatSr(int client, int track, float oldtime, float newtime)
{
    PrintToChatAll("NEW RECORD!!!");
    PrintToChatAll("NEW RECORD!!!");
    PrintToChatAll("NEW RECORD!!!");
}

// ^
public void OnPlayerBeatPb(int client, int track, float oldtime, float newtime)
{
    char sName[64];
    char sOldTime[64];
    char sNewTime[64];

    GetClientName(client, sName, sizeof(sName));

    FormatSeconds(oldtime, sOldTime, sizeof(sOldTime), true);
    FormatSeconds(newtime, sNewTime, sizeof(sNewTime), true);

    if (oldtime == 0.0)
    {
        PrintToChatAll("%s %s finished the map in %s.", PREFIX, sName, sNewTime);
    }
    else
    {
        PrintToChatAll("%s %s beat pb of %s with new time of %s", PREFIX, sName, sOldTime, sNewTime);
    }
}

// ^
public void OnPlayerFinishedTrack(int client, int track, float time, float pb)
{
    char sName[64];
    char sTime[64];
    char sPb[64];

    GetClientName(client, sName, sizeof(sName));
    FormatSeconds(time, sTime, sizeof(sTime), true);
    FormatSeconds(pb, sPb, sizeof(sPb), true);

    PrintToChatAll("%s %s finished track %i in %s (pb: %s).", PREFIX, sName, track, sTime, sPb);
}

//=================================
// DB
//=================================

void SetupDB()
{
    /**
     * Setup and connect to temp database settings.
    */
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

    g_hDB.Query(DB_ErrorHandler, "CREATE TABLE IF NOT EXISTS zones(id INTEGER PRIMARY KEY, map TEXT, track INTEGER, point1x REAL, point1y REAL, point2x REAL, point2y REAL, height REAL);", _);

    g_bDBLoaded = true;
    PrintToServer("%s Zone database successfully loaded!", PREFIX);

    CloseHandle(hKeyValues);
}

void SaveZones(int client)
{
    if (!g_bDBLoaded)
    {
        PrintToChat(client, "%s \x02ERROR: \x07Database not loaded. Cannot save zone!", PREFIX);
        return;
    }

    /**
     * Make sure zone points are set up, then save to db.
    */

    g_bIsZoneValid[g_pInfo[client].iEditingTrack] = true;

    SetupZonePoints(g_fZonePoints[g_pInfo[client].iEditingTrack]);
    CreateTrigger(g_pInfo[client].iEditingTrack);

    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'zones' WHERE map = '%s' AND track = %i", g_sMapName, g_pInfo[client].iEditingTrack);

    g_hDB.Query(DB_CreateZoneHandler, sQuery, client);
}


void LoadZones()
{
    if (!g_bDBLoaded || g_hDB == null)
    {
        return;
    }

    /**
     * Query db for zone points.
    */

    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'zones' WHERE map = '%s'", g_sMapName);

    g_hDB.Query(DB_LoadZoneHandler, sQuery, _);
}

void CreateZoneRow(int client)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "INSERT INTO zones(map, track, point1x, point1y, point2x, point2y, height) VALUES ('%s', %i, %f, %f, %f, %f, %f)", g_sMapName, g_pInfo[client].iEditingTrack, g_fZonePoints[g_pInfo[client].iEditingTrack][0][0], g_fZonePoints[g_pInfo[client].iEditingTrack][0][1], g_fZonePoints[g_pInfo[client].iEditingTrack][2][0], g_fZonePoints[g_pInfo[client].iEditingTrack][2][1], g_fZonePoints[g_pInfo[client].iEditingTrack][0][2]);

    g_hDB.Query(DB_ErrorHandler, sQuery, _);
}

void UpdateZoneRow(int id, int client)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "UPDATE zones SET point1x = %f, point1y = %f, point2x = %f, point2y = %f, height = %f WHERE id = %i", g_fZonePoints[g_pInfo[client].iEditingTrack][0][0], g_fZonePoints[g_pInfo[client].iEditingTrack][0][1], g_fZonePoints[g_pInfo[client].iEditingTrack][2][0], g_fZonePoints[g_pInfo[client].iEditingTrack][2][1], g_fZonePoints[g_pInfo[client].iEditingTrack][0][2], id);

    g_hDB.Query(DB_ErrorHandler, sQuery, _);
}

void RemoveZoneRow(int track)
{
    char sQuery[256];

    Format(sQuery, sizeof(sQuery), "SELECT * FROM 'zones' WHERE map = '%s' AND track = %i", g_sMapName, track);

    g_hDB.Query(DB_RemoveZoneHandler, sQuery, _);
}

public void DB_CreateZoneHandler(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", PREFIX, error);
        return;
    }

    /**
     * If there are no zones setup already, create a new row for it, otherwise
     * overwrite the current zone.
    */

    if (results.RowCount == 0)
    {
        CreateZoneRow(client);
    }
    else
    {
        UpdateZoneRow(results.FetchInt(0), client);
    }

    PrintToChat(client, "%s Successfully created zone!", PREFIX);
}

public void DB_LoadZoneHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null)
    {
        SetFailState("%s DB error. (%s)", PREFIX, error);
        return;
    }

    int iLoadingTrack;

    /**
     * If there are no zones to load, don't continue.
    */

    if (results.RowCount == 0)
    {
        return;
    }

    /**
     * Get important points from db for each zone, and calculate the rest of the points,
     * then create the trigger for it.
    */
    while (results.FetchRow())
    {
        iLoadingTrack = results.FetchInt(2);

        g_fZonePoints[iLoadingTrack][0][0] = results.FetchFloat(3);
        g_fZonePoints[iLoadingTrack][0][1] = results.FetchFloat(4);
        g_fZonePoints[iLoadingTrack][0][2] = results.FetchFloat(7);

        g_fZonePoints[iLoadingTrack][2][0] = results.FetchFloat(5);
        g_fZonePoints[iLoadingTrack][2][1] = results.FetchFloat(6);
        g_fZonePoints[iLoadingTrack][2][2] = results.FetchFloat(7);

        g_bIsZoneValid[iLoadingTrack] = true;
        
        SetupZonePoints(g_fZonePoints[iLoadingTrack]);
        CreateTrigger(iLoadingTrack);
    }
}

public void DB_RemoveZoneHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null)
    {
        SetFailState("Error (%s)", error);
        return;
    }

    if (results.RowCount != 1)
    {
        /**
         * There should never be more than 1 row for this query so something
         * is fucked if there is.
        */

        return;
    }

    char sQuery[256];
    int  iRowId;
    int  iTrack;

    /**
     * Delete the db row.
    */

    while (results.FetchRow())
    {
        iRowId = results.FetchInt(0);
        iTrack = results.FetchInt(2);

        Format(sQuery, sizeof(sQuery), "DELETE FROM 'zones' WHERE id = %i", iRowId);
        g_hDB.Query(DB_ErrorHandler, sQuery, _);

        g_bIsZoneValid[iTrack] = false;
    }
}

//=================================
// Timers
//=================================

public Action DrawGridSnap(Handle timer, int client)
{
    /**
     * Check if the player is in the zone menu. If they aren't,
     * stop drawing the grid snap.
    */

    if (!g_pInfo[client].bIsCreatingZone && IsValidClient(client))
    {
        ClearTimer(g_pInfo[client].hSnapTimer);
        return Plugin_Stop;
    }

    /**
     * Find closest snap point and draw it.
    */

    g_fSnapPoint[client] = g_fOrigin[client];

    ToClosestPoint(g_fSnapPoint[client], g_iSnapSize);

    TE_SetupBeamPoints(g_fOrigin[client], g_fSnapPoint[client], g_iBeam, 0, 0, 0, 0.1, 2.0, 2.0, 1, 0.0, {255, 255, 255, 255}, 5);
    TE_SendToAll();

    return Plugin_Continue;
}

public Action DrawZoneLoop(Handle timer, int client)
{
    /**
     * Loop through all zones and draw them.
    */

    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_bIsZoneValid[i])
        {
            DrawZone(client, g_fZonePoints[i], g_iBeam, 5.0, g_iTrackColors[i], 0);
        }
    }
}

public int MenuHandler_Zone(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        if (StrEqual(sInfo, "create"))
        {
            g_pInfo[client].bIsCreatingZone = true;
            g_pInfo[client].hSnapTimer = CreateTimer(0.1, DrawGridSnap, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

            DisplayCreateZoneMenu(client);
        }
        else if (StrEqual(sInfo, "remove"))
        {
            DisplayRemoveZoneMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public int MenuHandler_CreateZone(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char  sInfo[16];
        int   iPoint;

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        /**
         * Get selected point (shitty ternary stuff because I didn't plan ahead)
        */

        iPoint = StrContains(sInfo, "point") != -1 ? StrContains(sInfo, "1") != -1 ? 0 : 1 : -1;

        /**
         * If the player selected point 1 or 2, set that point to snap pos.
        */

        if (iPoint != -1)
        {
            g_fSelectedPoints[client][iPoint] = g_fSnapPoint[client];
            PrintToChat(client, "%s Set point %i at (%.0f, %.0f, %.0f).", PREFIX, iPoint + 1, (g_fSelectedPoints[client][iPoint][0]), (g_fSelectedPoints[client][iPoint][1]), (g_fSelectedPoints[client][iPoint][2]));
        }

        if (StrEqual(sInfo, "save"))
        {
            /**
             * Setup and save new zone points from new positions.
            */

            g_fZonePoints[g_pInfo[client].iEditingTrack][0] = g_fSelectedPoints[client][0];
            g_fZonePoints[g_pInfo[client].iEditingTrack][2] = g_fSelectedPoints[client][1];
            SaveZones(client);
        }
        else if (StrEqual(sInfo, "snap"))
        {
            /**
             * Increase/limit snap size.
            */

            g_iSnapSize *= 2;

            if (g_iSnapSize > 256)
                g_iSnapSize = 16;
        }
        else if (StrEqual(sInfo, "track"))
        {
            /**
             * Change editing track. If it's over 4 set it back down to 0.
            */

            g_pInfo[client].iEditingTrack++;
            
            g_pInfo[client].iEditingTrack %= 4;
        }
        
        DisplayCreateZoneMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        g_pInfo[client].bIsCreatingZone = false;
        DisplayParentZoneMenu(client);
    }
    else if (action == MenuAction_Cancel)
    {
        g_pInfo[client].bIsCreatingZone = false;
    }
    else
    {
        delete menu;
    }

    return 0;
}

public int MenuHandler_RemoveZone(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[64];
        char sSub[3];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        /**
         * Loop through each zone and get the "short" name for it (track<index>).
         * Done this way to support more zones in the future.
        */

        for (int i = 0; i < MAXZONES; i++)
        {
            Format(sSub, sizeof(sSub), "t%i", i);

            /**
             * Check if the short name for each track is the same as the selected one.
            */

            if (StrEqual(sInfo, sSub))
            {
                /**
                 * If it is, confirm that the player wants to delete the zone.
                */

                g_pInfo[client].iEditingTrack = i;

                DisplayConfirmMenu(client);

                return 0;
            }
        }

        DisplayRemoveZoneMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        DisplayParentZoneMenu(client);
    }
    else
    {
        delete menu;
    }

    return 0;
}

public int MenuHandler_Confirm(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[64];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }
        
        if (StrEqual(sInfo, "yes"))
        {
            /**
             * If the player confirms deletion, remove zone from db and delete the trigger for entering/exiting.
            */

            RemoveZoneRow(g_pInfo[client].iEditingTrack);
            g_bIsZoneValid[g_pInfo[client].iEditingTrack] = false;

            if (IsValidEntity(g_iTrigger[g_pInfo[client].iEditingTrack]))
            {
                RemoveEntity(g_iTrigger[g_pInfo[client].iEditingTrack]);
            }

            PrintToChat(client, "%s Succesfully removed track '%s'", PREFIX, g_sTrackNames[g_pInfo[client].iEditingTrack]);
        }
        
        DisplayRemoveZoneMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        DisplayRemoveZoneMenu(client);
    }
    else
    {
        delete menu;
    }

    return 0;
}

//=================================
// Menus
//=================================

void DisplayParentZoneMenu(int client)
{
    Menu hMenu = new Menu(MenuHandler_Zone);

    hMenu.SetTitle("Zone Menu");

    hMenu.AddItem("create", "Add Zone");
    hMenu.AddItem("remove", "Remove Zone");
    hMenu.ExitButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void DisplayCreateZoneMenu(int client)
{
    char sText[64];
    Format(sText, sizeof(sText), "Snap Size: %i", g_iSnapSize);

    Menu hMenu = new Menu(MenuHandler_CreateZone);

    hMenu.SetTitle("Create Zone");

    hMenu.AddItem("point1", "Set Point 1");
    hMenu.AddItem("point2", "Set Point 2\n ");
    hMenu.AddItem("save", "Save\n ");
    hMenu.AddItem("snap", sText);

    Format(sText, sizeof(sText), "Track: %s", g_sTrackNames[g_pInfo[client].iEditingTrack]);

    hMenu.AddItem("track", sText);
    hMenu.ExitButton = true;
    hMenu.ExitBackButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void DisplayRemoveZoneMenu(int client)
{
    char sDisplay[64];
    char sInfo[3];

    Menu hMenu = new Menu(MenuHandler_RemoveZone);

    hMenu.SetTitle("Remove Zone");

    /**
     * Loop through each valid zone and display it in delete menu.
    */

    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_bIsZoneValid[i])
        {
            Format(sDisplay, sizeof(sDisplay), "%s", g_sTrackNames[i]);
            Format(sInfo, sizeof(sInfo), "t%i", i);
            hMenu.AddItem(sInfo, sDisplay);
        }
    }

    if (hMenu.ItemCount == 0)
    {
        hMenu.AddItem("empty", "No zones on this map");
    }

    hMenu.ExitButton = true;
    hMenu.ExitBackButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void DisplayConfirmMenu(int client)
{
    char sTitle[64];

    Format(sTitle, sizeof(sTitle), "Confirm deletion of:\n'%s'?", g_sTrackNames[g_pInfo[client].iEditingTrack]);

    Menu hMenu = new Menu(MenuHandler_Confirm);

    hMenu.SetTitle(sTitle);

    hMenu.AddItem("yes", "Yes");
    hMenu.AddItem("no", "No");

    hMenu.ExitButton = true;
    hMenu.ExitBackButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

//=================================
// Commands
//=================================

public Action CMD_Zone(int client, int args)
{
    DisplayParentZoneMenu(client);

    return Plugin_Handled;
}

public Action CMD_Reset(int client, int args)
{
    if (!g_bIsZoneValid[g_pInfo[client].iCurrentTrack])
    {
        /**
         * If the bonus zone got deleted while they were on it, try to send them back
         * to the main zone and try resetting again.
         * If there is no main zone let them know.
        */

        if (g_pInfo[client].iCurrentTrack == Track_BonusStart)
        {
            g_pInfo[client].iCurrentTrack = Track_MainStart;
            CMD_Reset(client, 0);
            return Plugin_Handled;
        }
        else
        {
            PrintToChat(client, "%s No track found on map '%s'.", PREFIX, g_sMapName);
            return Plugin_Handled;
        }
    }

    StopTimer(client);

    /**
     * The divide by 2 is to "lower" the track number since I didn't plan ahead and made the arrays different sizes.
     *
     * Since there are 4 tracks, 0 and 2 are the starts for main and bonus track respectively, but in the
     * custom spawnpoint array 0 is main and 1 is bonus.
     * That means dividing by the current track "lowers" it to the correct number for custom spawns.
     *
     * Yeah it's stupid I know but it was easier than redoing both the arrays.
    */

    if (g_bHasCustomSpawn[client][g_pInfo[client].iCurrentTrack / 2])
    {
        TeleportEntity(client, g_fSpawnPoint[client][g_pInfo[client].iCurrentTrack / 2], g_fSpawnAngles[client][g_pInfo[client].iCurrentTrack / 2], { 0.0, 0.0, 0.0 });
    }
    else
    {
        float fOrigin[3];
        vecavg(fOrigin, g_fZonePoints[g_pInfo[client].iCurrentTrack][0], g_fZonePoints[g_pInfo[client].iCurrentTrack][2]);
        TeleportEntity(client, fOrigin, NULL_VECTOR, { 0.0, 0.0, 0.0 });
    }

    return Plugin_Handled;
}

public Action CMD_Main(int client, int args)
{
    if (!g_bIsZoneValid[Track_MainStart])
    {
        PrintToChat(client, "%s No track found on map '%s'.", PREFIX, g_sMapName);
        return Plugin_Handled;
    }

    int iPreviousTrack = g_pInfo[client].iCurrentTrack;

    g_pInfo[client].iCurrentTrack = Track_MainStart;

    /**
     * If the player switched from a different track
    */

    if (iPreviousTrack != Track_MainStart)
    {
        Call_StartForward(g_hPlayerTrackChangeForward);

        Call_PushCell(client);

        Call_Finish();
    }

    CMD_Reset(client, 0);

    return Plugin_Handled;
}

public Action CMD_Bonus(int client, int args)
{
    if (!g_bIsZoneValid[Track_BonusStart])
    {
        PrintToChat(client, "%s No bonus found on map '%s'.", PREFIX, g_sMapName);
        return Plugin_Handled;
    }

    int iPreviousTrack = g_pInfo[client].iCurrentTrack;

    g_pInfo[client].iCurrentTrack = Track_BonusStart;

    /**
     * If the player is switching from a different track
    */

    if (iPreviousTrack != Track_BonusStart)
    {
        Call_StartForward(g_hPlayerTrackChangeForward);

        Call_PushCell(client);

        Call_Finish();
    }

    CMD_Reset(client, 0);

    return Plugin_Handled;
}

public Action CMD_End(int client, int args)
{
    /**
     * Arrays are set up so it's start, end, start, end, ...
     * iCurrentTrack is the start track, so adding 1 gets the
     * end track.
    */

    if (!g_bIsZoneValid[g_pInfo[client].iCurrentTrack + 1])
    {
        PrintToChat(client, "%s No end found for current track.", PREFIX);
        return Plugin_Handled;
    }
    
    StopTimer(client);

    float fOrigin[3];

    vecavg(fOrigin, g_fZonePoints[g_pInfo[client].iCurrentTrack + 1][0], g_fZonePoints[g_pInfo[client].iCurrentTrack + 1][2]);

    TeleportEntity(client, fOrigin, NULL_VECTOR, { 0.0, 0.0, 0.0 });

    return Plugin_Handled;
}

public Action CMD_SetSpawn(int client, int args)
{
    int iTrack = g_pInfo[client].iCurrentTrack;

    if (g_pInfo[client].iInZone != iTrack)
    {
        PrintToChat(client, "%s Must be in selected zone to set spawnpoint.", PREFIX);
        return Plugin_Handled;
    }

    float fAngles[3];

    GetClientEyeAngles(client, fAngles);

    /**
     * Divide by 2 is for the same reason explained earlier (different sized arrays)
    */

    g_fSpawnPoint[client][iTrack / 2]     = g_fOrigin[client];
    g_fSpawnAngles[client][iTrack / 2]    = fAngles;
    g_bHasCustomSpawn[client][iTrack / 2] = true;

    PrintToChat(client, "%s Saved spawn.", PREFIX);

    return Plugin_Handled;
}

public Action CMD_DelSpawn(int client, int args)
{
    int iTrack = g_pInfo[client].iCurrentTrack;

    if (!g_bHasCustomSpawn[client][iTrack / 2])
    {
        PrintToChat(client, "%s No custom spawn set for current track.", PREFIX);
        return Plugin_Handled;
    }

    g_bHasCustomSpawn[client][iTrack / 2] = false;
    PrintToChat(client, "%s Removed custom spawn.", PREFIX);
    
    return Plugin_Handled;
}

//=================================
// Other
//=================================

void ClearPlayerInfo(int client)
{
    g_pInfo[client].bIsCreatingZone = false;
    g_pInfo[client].iInZone         = -1;
    g_pInfo[client].iCurrentTrack   = Track_MainStart;
    g_pInfo[client].iEditingTrack   = Track_MainStart;
    
    ClearTimer(g_pInfo[client].hZoneTimer);
    ClearTimer(g_pInfo[client].hSnapTimer);
}

void DrawZone(int client, float points[8][3], int beam, float width, const int color[4], int speed)
{
    if (!IsValidClient(client))
    {
        return;
    }

    int j = 1;
    int l = 5;

    /**
     * Draw bottom 4 lines, and vertical beams on corners
    */

    for (int i = 0; i < 8; i++)
    {
        if (j > 3 || i == 4)
        {
            j = 0;
        }

        TE_SetupBeamPoints(points[i], points[j], beam, 0, 0, 0, TIMER_ZONE_UPDATERATE, width, width, 0, 0.0, color, speed);

        TE_SendToClient(client);

        j++;
    }

    /**
     * Draw the top 4 lines.
    */

    for (int k = 4; k < 8; k++)
    {
        if (l > 7)
        {
            l = 4;
        }
            
        TE_SetupBeamPoints(points[k], points[l], beam, 0, 0, 0, TIMER_ZONE_UPDATERATE, width, width, 0, 0.0, color, speed);
        TE_SendToClient(client);
        
        l++;
    }
}

void HandleZoneMovement(int client)
{
    if (g_pInfo[client].iInZone == -1)
    {
        return;
    }

    /**
     * If the player is in the air and in the start zone of specified track, limit their speed to 250 u/s
    */

    if (!(GetEntityFlags(client) & FL_ONGROUND) && g_pInfo[client].iInZone == g_pInfo[client].iCurrentTrack)
    {
        float fVel[3];

        GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);

        float fCurrentSpeed = SquareRoot(Pow(fVel[0], 2.0) + Pow(fVel[1], 2.0));

        /*
         * Thanks to m_bNightStalker on alliedmods.net
         * https://forums.alliedmods.net/showthread.php?t=269935
        */

        if (fCurrentSpeed > 250.0)
        {
            float fDiv = fCurrentSpeed / 250.0;

            if (fDiv != 0.0)
            {
                fVel[0] /= fDiv;
                fVel[1] /= fDiv;
                TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVel);
            }
        }
    }
}

void ToClosestPoint(float input[3], int amount)
{
    for (int i = 0; i < 2; i++)
    {
        input[i] = float(RoundToNearest(input[i] / amount) * amount);
    }
}

void CreateTrigger(int track)
{
    float fOrigin[3];
    float fMax[3];
    float fMin[3];

    /**
     * Create local max/mins and origin
    */

    fOrigin[0] = avg(g_fZonePoints[track][0][0], g_fZonePoints[track][2][0]);
    fOrigin[1] = avg(g_fZonePoints[track][0][1], g_fZonePoints[track][2][1]);
    fOrigin[2] = g_fZonePoints[track][0][2];

    /**
     * Subtract 16 from both sides so timer starts when center of player leaves the zone, instead of
     * waiting until the player fully exits the zone.
    */

    fMax[0] = max(g_fZonePoints[track][0][0], g_fZonePoints[track][2][0]) - fOrigin[0] - 16.0;
    fMax[1] = max(g_fZonePoints[track][0][1], g_fZonePoints[track][2][1]) - fOrigin[1] - 16.0;
    fMax[2] = DEFAULT_ZONE_HEIGHT - 27.0; // - 27 so bottom half of body has to be in the visible zone before start/end touch

    fMin[0] = -fMax[0];
    fMin[1] = -fMax[1];
    fMin[2] = -3.0; // Make entity go into floor a bit, otherwise crouching causes end touch for some reason

    g_iTrigger[track] = CreateEntityByName("trigger_multiple");

    DispatchKeyValue(g_iTrigger[track], "StartDisabled", "1");
    DispatchKeyValue(g_iTrigger[track], "spawnflags", "1");

    SetEntProp(g_iTrigger[track], Prop_Send, "m_fEffects", 32);
    SetEntityModel(g_iTrigger[track], "models/props/cs_office/vending_machine.mdl");
    TeleportEntity(g_iTrigger[track], fOrigin, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(g_iTrigger[track]);
    SetEntPropVector(g_iTrigger[track], Prop_Send, "m_vecMaxs", fMax);
    SetEntPropVector(g_iTrigger[track], Prop_Send, "m_vecMins", fMin);
    SetEntProp(g_iTrigger[track], Prop_Send, "m_nSolidType", 2);

    AcceptEntityInput(g_iTrigger[track], "Enable");

    //HookSingleEntityOutput(g_iTrigger, "OnStartTouch", OnStartTouch);
	//HookSingleEntityOutput(g_iTrigger, "OnEndTouch", OnEndTouch);
    SDKHook(g_iTrigger[track], SDKHook_StartTouchPost, OnStartTouch);
    SDKHook(g_iTrigger[track], SDKHook_EndTouchPost, OnEndTouch);

    g_bIsZoneValid[track] = true;
}

/*
      5---------6 
     /|        /|
    / |       / |
   4---------7  |
   |  |      |  |
   |  |      |  |
   |  1------|--2
   | /       | /
   0---------3/
*/
void SetupZonePoints(float zone[8][3])
{
    zone[1][0] = zone[0][0];
    zone[1][1] = zone[2][1];

    zone[3][0] = zone[2][0];
    zone[3][1] = zone[0][1];
    
    for (int i = 0; i < 4; i++)
    {
        zone[i][2] = zone[0][2];
        zone[i + 4][2] = zone[0][2] + DEFAULT_ZONE_HEIGHT;

        for (int j = 0; j < 2; j++)
        {
            zone[i + 4][j] = zone[i][j];
        }
    }
}

//=================================
// Natives
//=================================

public int Native_IsPlayerInZone(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return -1;
    }
    
    return g_pInfo[GetNativeCell(1)].iInZone;
}

public int Native_GetPlayerTrack(Handle plugin, int param)
{
    if (!IsValidClient(GetNativeCell(1)))
    {
        return -1;
    }

    return g_pInfo[GetNativeCell(1)].iCurrentTrack;
}
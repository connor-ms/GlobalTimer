#include <globaltimer>

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define MAXZONES 4

enum struct PlayerZoneInfo
{
    /**
     * Zone editing/creating
     */
    
    bool     bIsCreatingZone;       // Whether a player is in the create zone menu.
    bool     bFinishedCreatingZone; // When true, allows player to confirm zone.
    bool     bEditingHeight;        // Whether a player is editing the zone height.
    int      iTrack;                // Track the player is creating a zone for. (Main/Bonus)
    int      iType;                 // Track type. (see g_sZoneTypes)
    int      iSnapSize;             // Snap size of grid for zone points.
    int      iEditStyle;            // Edit style for deciding zone points. (Location or viewangles)
    int      iZoneHeight;           // Height of zone. By default 140 units.
    Handle   hRenderGridSnap;       // Timer for drawing zone being created.

    /**
     * Timer related
     */

    int      iCurrentTrack;         // Current track the player is running.
    int      iPreviousLeftTick;     // The last tick the player left a zone. Used to prevent /end abuse.
};

enum struct Zone
{
    int      iEntityIndex;          // Entity index for zone.
    int      iBorderEntityIndex;    // Secondary entity for start touch.
    int      iTrack;                // Main/Bonus.
    int      iType;                 // Start/End.
    bool     bValid;                // Whether or not zone entity has been created.
};

PlayerZoneInfo g_eInfo[MAXPLAYERS + 1];
Zone           g_eZones[MAXZONES];
DB             g_eDB;

int   g_iZoneCount;
float g_fZonePoints[MAXZONES][8][3];
float g_fZoneOrigin[MAXZONES][3];
int   g_iBeam[MAXZONES][12];

float g_fSnapPoint[MAXPLAYERS + 1][3];    // Since enum structs don't support arrays :(
float g_fSetPoints[MAXPLAYERS + 1][2][3]; // To save the point for start/end point set in zone menu

bool g_bLate;

int g_iBeamIndex;

char g_sBeamName[128];
char g_sBeamPath[256];

Handle g_hLeaveZoneForward;
Handle g_hLeaveZoneForwardPre;
Handle g_hEnterZoneForward;
Handle g_hTrackChangeForward;

char g_sMapName[128];

char g_sTracks[2][5] =
{
    "Main",
    "Bonus"
};

char g_sZoneTypes[][] =
{
    "Start",
    "End"
};

/**
 * Color values for each zone. Set up to be track->type.
 * Example: if the first row was { "0 0 255", "255 0 0" }
 * it would mean for the track "Main", "Start" color would
 * be "0 0 255", and "End" would be "255 0 0". 
 */

char g_sZoneColors[][][] =
{
    { "255 255 255", "255 255 255" },
    { "255 255 255", "255 255 255" }
};

/**
 * Same as above, but converted to integers.
 * (used for drawing beams)
 */

int g_iRealZoneColors[][][] =
{
    { { 255, 255, 255, 255 }, { 255, 255, 255, 255 } },
    { { 255, 255, 255, 255 }, { 255, 255, 255, 255 } }
};

char g_sEditStyles[][] =
{
    "Mouse",
    "Location"
};

public Plugin myinfo = 
{
    name        = "[GlobalTimer] Zones",
    description = "Zone support for timer.",
    author      = "Connor",
    version     = VERSION,
    url         = URL
};

public void OnPluginStart()
{
    SetupDB();

    g_hLeaveZoneForward   = CreateGlobalForward("OnPlayerLeaveZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hLeaveZoneForwardPre = CreateGlobalForward("OnPlayerLeaveZonePre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hEnterZoneForward   = CreateGlobalForward("OnPlayerEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hTrackChangeForward = CreateGlobalForward("OnPlayerTrackChange", ET_Event, Param_Cell, Param_Cell);

    HookEvent("round_start", OnRoundStart);
    HookEvent("player_spawn", OnPlayerSpawn);

    /**
     * Admin commands
     */
    
    RegAdminCmd("sm_zone", CMD_Zone, ADMFLAG_CHANGEMAP, "Opens zone menu.");

    /**
     * Player commands
     */

    RegConsoleCmd("sm_restart", CMD_Restart, "Restarts your timer.");
    RegConsoleCmd("sm_main",    CMD_Main,    "Sets your track to main.");
    RegConsoleCmd("sm_bonus",   CMD_Bonus,   "Sets your track to bonus.");
    RegConsoleCmd("sm_end",     CMD_End,     "Teleports you to end of current track.");

    /**
     * Aliases
     */

    RegConsoleCmd("sm_r", CMD_Restart, "Restarts your timer.");
    RegConsoleCmd("sm_s", CMD_Main,    "Sets your track to main.");
    RegConsoleCmd("sm_b", CMD_Bonus,   "Sets your track to bonus.");

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

public void OnPluginEnd()
{
    RemoveAllZones();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_bLate = late;

    CreateNative("GetZoneOrigin", Native_GetZoneOrigin);

    return APLRes_Success;
}

//=================================
// Forwards
//=================================

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));

    AddFilesToDownloadTable();

    g_iBeamIndex = PrecacheModel(g_sBeamName, true);
    PrecacheModel("models/props/cs_office/vending_machine.mdl", true);

    for (int i = 0; i < MAXZONES; i++)
    {
        g_eZones[i].iEntityIndex = -1;
        g_eZones[i].bValid       = false;
        g_eZones[i].iTrack       = INVALID_TRACK;
        g_eZones[i].iType        = INVALID_ZONE;

        g_iZoneCount = 0;
    }
    
    DB_LoadZones();
}

public void OnRoundStart(Event event, const char[] name, bool broadcast)
{
    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_eZones[i].bValid)
        {
            CreateZoneEntities(i, g_eZones[i].iTrack, g_eZones[i].iType);
        }
    }
}

public void OnPlayerSpawn(Event event, const char[] name, bool broadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    int iZone = FindZoneIndex(g_eInfo[client].iTrack, g_eInfo[client].iType);

    if (iZone == -1 || !g_eZones[iZone].bValid)
    {
        return;
    }
    
    CMD_Restart(client, 0);
}

public void OnClientConnected(int client)
{
    /**
     * Zone editing/creating
     */

    g_eInfo[client].bIsCreatingZone       = false;
    g_eInfo[client].bFinishedCreatingZone = false;
    g_eInfo[client].bEditingHeight        = false;
    g_eInfo[client].iTrack                = 0;
    g_eInfo[client].iType                 = 0;
    g_eInfo[client].iSnapSize             = 16;
    g_eInfo[client].iEditStyle            = 0;
    g_eInfo[client].iZoneHeight           = 140;
    g_eInfo[client].hRenderGridSnap       = null;

    /**
     * Timer related
     */
    
    g_eInfo[client].iCurrentTrack         = Track_Main;
}

public void OnClientDisconnect(int client)
{
    ClearTimer(g_eInfo[client].hRenderGridSnap);
}

public void OnStartTouch(int entity, int client)
{
    for (int i = 0; i < MAXZONES; i++)
    {
        if (entity == g_eZones[i].iEntityIndex)
        {
            if (!IsClientConnected(client)) // just to make sure idk if it really makes a difference or not
            {
                return;
            }

            /**
             * If the player left a zone and entered this one on the same tick, don't call the
             * forward, because it means they teleported to it from inside another zone.
             */

            if (g_eInfo[client].iPreviousLeftTick == GetGameTickCount())
            {
                return;
            }

            Call_StartForward(g_hEnterZoneForward);

            Call_PushCell(client);
            Call_PushCell(GetGameTickCount());
            Call_PushCell(g_eZones[i].iTrack);
            Call_PushCell(g_eZones[i].iType);

            Call_Finish();

            g_eInfo[client].iPreviousLeftTick = GetGameTickCount();
        }
    }
}

public void OnEndTouch(int entity, int client)
{
    for (int i = 0; i < MAXZONES; i++)
    {
        if (entity == g_eZones[i].iEntityIndex)
        {
            if (!IsClientConnected(client))
            {
                return;
            }

            if (g_eInfo[client].iPreviousLeftTick == GetGameTickCount())
            {
                return;
            }

            Call_StartForward(g_hLeaveZoneForward);

            Call_PushCell(client);
            Call_PushCell(GetGameTickCount());
            Call_PushCell(g_eZones[i].iTrack);
            Call_PushCell(g_eZones[i].iType);

            Call_Finish();

            g_eInfo[client].iPreviousLeftTick = GetGameTickCount();
        }

        if (entity == g_eZones[i].iBorderEntityIndex)
        {
            Call_StartForward(g_hLeaveZoneForwardPre);

            Call_PushCell(client);
            Call_PushCell(GetGameTickCount());
            Call_PushCell(g_eZones[i].iTrack);
            Call_PushCell(g_eZones[i].iType);

            Call_Finish();
        }
    }
}

//=================================
// Database
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

    DB_Query("CREATE TABLE IF NOT EXISTS zones(id INTEGER PRIMARY KEY, map TEXT, track INTEGER, type INTEGER, point1x REAL, point1y REAL, point2x REAL, point2y REAL, z REAL, height REAL);",
             "", DB_ErrorHandler, _);
}

void DB_SaveZone(int client, int id)
{
    if (!g_eDB.bConnected)
    {
        PrintToChat(client, "%s \x02Warning: \x07Database not connected. Zone will not be saved.", g_sPrefix);
        return;
    }

    char sQuery_SQLite[128];

    Format(sQuery_SQLite, 128, "SELECT * FROM 'zones' WHERE map = '%s' AND track = %i AND type = %i;", g_sMapName, g_eZones[id].iTrack, g_eZones[id].iType);

    DB_Query(sQuery_SQLite, "", DB_SaveZoneHandler, client);
}

void DB_SaveZoneHandler(Database db, DBResultSet results, const char[] error, int client)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    char sQuery_SQLite[256];
    char sQuery_MySQL[256];

    int iZoneIndex = FindZoneIndex(g_eInfo[client].iTrack, g_eInfo[client].iType);

    if (results.RowCount == 0)
    {
        Format(sQuery_SQLite, sizeof(sQuery_SQLite),
               "INSERT INTO zones(map, track, type, point1x, point1y, point2x, point2y, z, height) VALUES ('%s', %i, %i, %f, %f, %f, %f, %f, %i);",
               g_sMapName, g_eInfo[client].iTrack, g_eInfo[client].iType, g_fZonePoints[iZoneIndex][0][0], g_fZonePoints[iZoneIndex][0][1], g_fZonePoints[iZoneIndex][2][0],
               g_fZonePoints[iZoneIndex][2][1], g_fZonePoints[iZoneIndex][0][2], g_eInfo[client].iZoneHeight);

        DB_Query(sQuery_SQLite, sQuery_MySQL, DB_ErrorHandler, _);
    }
    else
    {
        Format(sQuery_SQLite, sizeof(sQuery_SQLite),
               "UPDATE zones SET point1x = %f, point1y = %f, point2x = %f, point2y = %f, z = %f, height = %i WHERE id = %i",
               g_fZonePoints[iZoneIndex][0][0], g_fZonePoints[iZoneIndex][0][1], g_fZonePoints[iZoneIndex][2][0],
               g_fZonePoints[iZoneIndex][2][1], g_fZonePoints[iZoneIndex][0][2], g_eInfo[client].iZoneHeight, results.FetchInt(0));

        DB_Query(sQuery_SQLite, sQuery_MySQL, DB_ErrorHandler, _);
    }

    LogMessage("%L created zone '[%s] %s' on map %s", client, g_sTracks[g_eZones[iZoneIndex].iTrack], g_sZoneTypes[g_eZones[iZoneIndex].iType], g_sMapName);
}

void DB_LoadZones()
{
    char sQuery_SQLite[128];

    Format(sQuery_SQLite, 128, "SELECT * FROM 'zones' WHERE map = '%s';", g_sMapName);

    DB_Query(sQuery_SQLite, "", DB_LoadZonesHandler, _);
}

void DB_LoadZonesHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null)
    {
        LogError("Database error. (%s)", error);
        return;
    }

    if (results.RowCount == 0)
    {
        return;
    }

    while (results.FetchRow())
    {
        int iZoneIndex = FindZoneIndex(results.FetchInt(2), results.FetchInt(3));

        if (iZoneIndex != -1)
        {
            /**
             * Delete the zone if it does exist, and use it's index for the new zone.
             */

            RemoveZone(iZoneIndex);
        }
        else
        {
            /**
             * Otherwise it's a new zone, so increase total zone count and use that as index.
             */

            iZoneIndex = g_iZoneCount;
            g_iZoneCount++;
        }

        g_fZonePoints[iZoneIndex][0][0] = results.FetchFloat(4);
        g_fZonePoints[iZoneIndex][0][1] = results.FetchFloat(5);
        g_fZonePoints[iZoneIndex][0][2] = results.FetchFloat(8);

        g_fZonePoints[iZoneIndex][2][0] = results.FetchFloat(6);
        g_fZonePoints[iZoneIndex][2][1] = results.FetchFloat(7);
        g_fZonePoints[iZoneIndex][2][2] = results.FetchFloat(8);

        SetupZonePoints(g_fZonePoints[iZoneIndex], results.FetchInt(9));
        CreateZoneEntities(iZoneIndex, results.FetchInt(2), results.FetchInt(3));
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
// Misc
//=================================

void CreateBeam(int &entity, float start[3], float end[3], char[] color)
{
    entity = CreateEntityByName("env_beam");

    if (entity != -1)
    {
        TeleportEntity(entity, start, NULL_VECTOR, NULL_VECTOR);
        SetEntityModel(entity, g_sBeamName);

        SetEntPropVector(entity, Prop_Data, "m_vecEndPos", end);
        SetEntPropFloat(entity,  Prop_Data, "m_fWidth", 2.0);
        SetEntPropFloat(entity,  Prop_Data, "m_fEndWidth", 2.0);
        SetEntPropFloat(entity,  Prop_Data, "m_fSpeed", 5.0);

        DispatchKeyValue(entity, "rendercolor", color);
        DispatchKeyValue(entity, "renderamt", "255");
        DispatchSpawn(entity);

        ActivateEntity(entity);
        AcceptEntityInput(entity, "TurnOn");
    }
}

void CreatePermanentZone(int client)
{
    /**
     * Make sure the zone being created doesn't exist already.
     */

    int iZoneIndex = FindZoneIndex(g_eInfo[client].iTrack, g_eInfo[client].iType);

    if (iZoneIndex != -1)
    {
        /**
         * Delete the zone if it does exist, and use it's index for the new zone.
         */
        
        RemoveZone(iZoneIndex);
    }
    else
    {
        /**
         * Otherwise it's a new zone, so increase total zone count and use that as index.
         */

        iZoneIndex = g_iZoneCount;
        g_iZoneCount++;
    }

    g_fZonePoints[iZoneIndex][0] = g_fSetPoints[client][0];
    g_fZonePoints[iZoneIndex][2] = g_fSetPoints[client][1];

    SetupZonePoints(g_fZonePoints[iZoneIndex], g_eInfo[client].iZoneHeight);
    CreateZoneEntities(iZoneIndex, g_eInfo[client].iTrack, g_eInfo[client].iType);
}

void CreateZoneEntities(int index, int track, int type)
{
    /**
     * Create 4 bottom beams
     */

    for (int i = 0; i < 4; i++)
    {
        CreateBeam(g_iBeam[index][i], g_fZonePoints[index][i], g_fZonePoints[index][(i + 1) % 4], g_sZoneColors[track][type]);

        /**
         * Create vertical beams
         */

        CreateBeam(g_iBeam[index][i + 8], g_fZonePoints[index][((i + 4) % 4) + 4], g_fZonePoints[index][i], g_sZoneColors[track][type]);

        /**
         * Create second row of beams
         */

        CreateBeam(g_iBeam[index][i + 4], g_fZonePoints[index][i + 4], g_fZonePoints[index][((i + 5) % 4) + 4], g_sZoneColors[track][type]);
    }

    CreateZoneEntity(index, track, type);
}

void AddFilesToDownloadTable()
{
    /**
     * First, read config file to find paths for files.
     */

    if (!ReadConfig())
    {
        LogError("Error reading zones config file.");
        return;
    }

    /**
     * Duplicate original path (to make it easier to add .vmt/.vtf to the end)
     */

    char sTemp[256];

    strcopy(sTemp, sizeof(sTemp), g_sBeamPath);

    /**
     * Append .vmt to end of path and add it to download table, then
     * replace it back to default again (without any extension), add
     * .vtf to the end and add that to download table.
     */

    StrCat(sTemp, sizeof(sTemp), ".vmt");
    AddFileToDownloadsTable(sTemp);

    strcopy(sTemp, sizeof(sTemp), g_sBeamPath);

    StrCat(sTemp, sizeof(sTemp), ".vtf");
    AddFileToDownloadsTable(sTemp);
}

bool ReadConfig()
{
    bool bSuccess;

    bSuccess = GetKV("texture", "model", g_sBeamName, sizeof(g_sBeamName), "configs/GlobalTimer/zones.cfg");
    bSuccess = GetKV("texture", "path", g_sBeamPath, sizeof(g_sBeamPath), "configs/GlobalTimer/zones.cfg");

    for (int i = 0; i < 2; i++)
    {
        for (int j = 0; j < 2; j++)
        { 
            char sKV[32];
            Format(sKV, sizeof(sKV), "%s-%s", g_sTracks[i], g_sZoneTypes[j]);

            bSuccess = GetKV(sKV, "color", g_sZoneColors[i][j], 32, "configs/GlobalTimer/zones.cfg");

            char sExplodedColors[3][4];
            
            ExplodeString(g_sZoneColors[i][j], " ", sExplodedColors, 3, 4);

            for (int k = 0; k < 3; k++)
            {
                g_iRealZoneColors[i][j][k] = StringToInt(sExplodedColors[k]);
            }

            g_iRealZoneColors[i][j][3] = 255;
        }
    }

    return bSuccess;
}

public bool TraceEntityFilterPlayer(int entity, int mask)
{
    return entity > MAXPLAYERS || entity == 0;
}

void ToClosestPoint(float input[3], int amount)
{
    for (int i = 0; i < 2; i++)
    {
        input[i] = float(RoundToNearest(input[i] / amount) * amount);
    }
}

void DrawTempZone(int client)
{
    float fPoints[8][3];

    fPoints[0] = g_fSetPoints[client][0];

    if (g_eInfo[client].bFinishedCreatingZone)
    {
        fPoints[2] = g_fSetPoints[client][1];
    }
    else
    {
        fPoints[2] = g_fSnapPoint[client];
    }

    SetupZonePoints(fPoints, g_eInfo[client].iZoneHeight);

    DrawZone(client, fPoints, g_iBeamIndex, 2.0, 0);
}

void DrawZone(int client, float points[8][3], int beam, float width, int speed)
{
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

        TE_SetupBeamPoints(points[i], points[j], beam, 0, 0, 0, 0.1, width, width, 0, 0.0, g_iRealZoneColors[g_eInfo[client].iTrack][g_eInfo[client].iType], speed);
        TE_SendToAll();

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
            
        TE_SetupBeamPoints(points[k], points[l], beam, 0, 0, 0, 0.1, width, width, 0, 0.0, g_iRealZoneColors[g_eInfo[client].iTrack][g_eInfo[client].iType], speed);
        TE_SendToAll();
        
        l++;
    }
}

/*
     5---------6
    /|        /|
   4---------7 |
   | |       | |
   | 1-------|-2
   |/        |/
   0---------3
 */

void SetupZonePoints(float zone[8][3], int height)
{
    zone[1][0] = zone[0][0];
    zone[1][1] = zone[2][1];

    zone[3][0] = zone[2][0];
    zone[3][1] = zone[0][1];
    
    for (int i = 0; i < 4; i++)
    {
        zone[i][2] = zone[0][2];
        zone[i + 4][2] = zone[0][2] + height;

        for (int j = 0; j < 2; j++)
        {
            zone[i + 4][j] = zone[i][j];
        }
    }
}

void CreateZoneEntity(int id, int track, int type)
{
    char sTargetName[32];

    Format(sTargetName, sizeof(sTargetName), "gt_trig_%i_%i", track, type);

    /**
     * Set up mins/maxs
     */

    float fOrigin[3];
    float fMin[3];
    float fMax[3];

    vecavg(fOrigin, g_fZonePoints[id][0], g_fZonePoints[id][2]);
    fOrigin[2] = g_fZonePoints[id][0][2];

    g_fZoneOrigin[id] = fOrigin;

    /**
     * Subtract 16 from both sides so timer starts when center of player leaves the zone, instead of
     * waiting until the player fully exits the zone.
     */

    fMax[0] = max(g_fZonePoints[id][0][0], g_fZonePoints[id][2][0]) - fOrigin[0] - 16.0;
    fMax[1] = max(g_fZonePoints[id][0][1], g_fZonePoints[id][2][1]) - fOrigin[1] - 16.0;
    fMax[2] = g_fZonePoints[id][4][2] - g_fZonePoints[id][0][2] - 27.0; // - 27 so bottom half of body has to be in the visible zone before start/end touch

    fMin[0] = -fMax[0];
    fMin[1] = -fMax[1];
    fMin[2] = -3.0; // Make entity go into floor a bit, otherwise crouching causes end touch for some reason

    g_eZones[id].iEntityIndex = CreateEntityByName("trigger_multiple");

    DispatchKeyValue(g_eZones[id].iEntityIndex, "StartDisabled", "1");
    DispatchKeyValue(g_eZones[id].iEntityIndex, "spawnflags", "1");
    DispatchKeyValue(g_eZones[id].iEntityIndex, "targetname", sTargetName);

    SetEntProp(g_eZones[id].iEntityIndex, Prop_Send, "m_fEffects", 32);
    SetEntityModel(g_eZones[id].iEntityIndex, "models/props/cs_office/vending_machine.mdl");
    TeleportEntity(g_eZones[id].iEntityIndex, fOrigin, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(g_eZones[id].iEntityIndex);
    SetEntPropVector(g_eZones[id].iEntityIndex, Prop_Send, "m_vecMaxs", fMax);
    SetEntPropVector(g_eZones[id].iEntityIndex, Prop_Send, "m_vecMins", fMin);
    SetEntProp(g_eZones[id].iEntityIndex, Prop_Send, "m_nSolidType", 2);

    AcceptEntityInput(g_eZones[id].iEntityIndex, "Enable");

    //HookSingleEntityOutput(g_iTrigger, "OnStartTouch", OnStartTouch);
	//HookSingleEntityOutput(g_iTrigger, "OnEndTouch", OnEndTouch);
    SDKHook(g_eZones[id].iEntityIndex, SDKHook_StartTouchPost, OnStartTouch);
    SDKHook(g_eZones[id].iEntityIndex, SDKHook_EndTouchPost, OnEndTouch);

    g_eZones[id].bValid = true;
    g_eZones[id].iTrack = track;
    g_eZones[id].iType = type;
}

void RemoveAllZones()
{
    for (int i = 0; i < MAXZONES; i++)
    {
        RemoveZone(i);
    }
}

void RemoveZone(int id)
{
    if (!g_eZones[id].bValid)
    {
        return;
    }

    g_eZones[id].bValid = false;

    /**
     * Remove enter/exit trigger
     */

    RemoveEdict(g_eZones[id].iEntityIndex);

    /**
     * Remove outline beams
     */

    for (int i = 0; i < 12; i++)
    {
        AcceptEntityInput(g_iBeam[id][i], "Kill");
    }
}

int FindZoneIndex(int track, int type)
{
    /**
     * Finds the index of the zone that matches the track and type.
    */

    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_eZones[i].iTrack == track && g_eZones[i].iType == type)
        {
            return i;
        }
    }

    return -1;
}

void RemoveZonePermanent(int client, int track)
{
    if (track == INVALID_TRACK)
    {
        int iZone = FindZoneIndex(g_eInfo[client].iTrack, g_eInfo[client].iType);

        RemoveZone(iZone);

        char sQuery_SQLite[128];

        Format(sQuery_SQLite, sizeof(sQuery_SQLite), "DELETE FROM zones WHERE track = %i AND type = %i;", g_eZones[iZone].iTrack, g_eZones[iZone].iType);

        DB_Query(sQuery_SQLite, "", DB_ErrorHandler, _);

        LogMessage("%L removed zone '[%s] %s' on map %s.", client, g_sTracks[g_eZones[iZone].iTrack], g_sZoneTypes[g_eZones[iZone].iType], g_sMapName);
    }
    else
    {
        /**
         * If the track is specified, remove all zones for that track.
         */

        for (int i = 0; i < MAXZONES; i++)
        {
            if (g_eZones[i].bValid && g_eZones[i].iTrack == track)
            {
                RemoveZone(i);
            }
        }

        char sQuery_SQLite[128];

        Format(sQuery_SQLite, sizeof(sQuery_SQLite), "DELETE FROM zones WHERE track = %i;", track);

        DB_Query(sQuery_SQLite, "", DB_ErrorHandler, _);

        LogMessage("%L removed all '[%s]' zones on map %s.", client, g_sTracks[track], g_sMapName);
    }
}

//=================================
// Timers
//=================================

public Action DrawZoneLoop(Handle timer, int client)
{
    if (timer == null)
    {
        LogError("Error starting zone drawing timer.");
        return Plugin_Handled;
    }

    /**
     * Draw grid snap
     */

    if (g_eInfo[client].iEditStyle == 0) // Using viewangles for points
    {
        float fAngles[3];
        float fOrigin[3];

        GetClientEyePosition(client, fOrigin);
        GetClientEyeAngles(client, fAngles);

        Handle trace = TR_TraceRayFilterEx(fOrigin, fAngles, MASK_ALL, RayType_Infinite, TraceEntityFilterPlayer);

        if (TR_DidHit(trace))
        {
            TR_GetEndPosition(g_fSnapPoint[client], trace);
        }

        CloseHandle(trace);
    }
    else // Using location for points
    {
        GetClientAbsOrigin(client, g_fSnapPoint[client]);
    }

    ToClosestPoint(g_fSnapPoint[client], g_eInfo[client].iSnapSize);

    /**
     * Draw "X" marker on snapped point.
     * If anyone has a "cleaner" way of doing this, feel free to share lol
     */

    float fMarkerPoints[4][3];

    fMarkerPoints[0][0] = g_fSnapPoint[client][0] - g_eInfo[client].iSnapSize / 2.0;
    fMarkerPoints[0][1] = g_fSnapPoint[client][1];
    fMarkerPoints[0][2] = g_fSnapPoint[client][2];

    fMarkerPoints[1][0] = g_fSnapPoint[client][0] + g_eInfo[client].iSnapSize / 2.0;
    fMarkerPoints[1][1] = g_fSnapPoint[client][1];
    fMarkerPoints[1][2] = g_fSnapPoint[client][2];

    fMarkerPoints[2][0] = g_fSnapPoint[client][0];
    fMarkerPoints[2][1] = g_fSnapPoint[client][1] - g_eInfo[client].iSnapSize / 2.0;
    fMarkerPoints[2][2] = g_fSnapPoint[client][2];

    fMarkerPoints[3][0] = g_fSnapPoint[client][0];
    fMarkerPoints[3][1] = g_fSnapPoint[client][1] + g_eInfo[client].iSnapSize / 2.0;
    fMarkerPoints[3][2] = g_fSnapPoint[client][2];

    TE_SetupBeamPoints(fMarkerPoints[0], fMarkerPoints[1], g_iBeamIndex, 0, 0, 0, 0.1, 2.0, 2.0, 0, 0.0, {255, 255, 255, 255}, 0.0);
    TE_SendToAll();

    TE_SetupBeamPoints(fMarkerPoints[2], fMarkerPoints[3], g_iBeamIndex, 0, 0, 0, 0.1, 2.0, 2.0, 0, 0.0, {255, 255, 255, 255}, 0.0);
    TE_SendToAll();

    /**
     * Draw temporary zone
     */

    if (g_eInfo[client].bIsCreatingZone || g_eInfo[client].bFinishedCreatingZone)
    {
        DrawTempZone(client);
    }

    if (g_eInfo[client].bEditingHeight)
    {
        /**
         * Don't allow the height to be < 10.
         */

        g_eInfo[client].iZoneHeight = RoundFloat(max(10.0, g_fSnapPoint[client][2] - g_fSetPoints[client][0][2]));
    }

    return Plugin_Continue;
}

//=================================
// Menus
//=================================

int MenuHandler_ZoneParent(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }
        
        float fOrigin[3];
        
        GetClientAbsOrigin(client, fOrigin);

        if (StrEqual(sInfo, "create"))
        {
            OpenCreateZoneMenu(client);
        }

        if (StrEqual(sInfo, "remove"))
        {
            OpenRemoveZoneMenu(client);
        }

        if (StrEqual(sInfo, "edit"))
        {
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_CreateZone(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }
        
        if (StrEqual(sInfo, "track"))
        {
            g_eInfo[client].iTrack++;

            g_eInfo[client].iTrack %= 2;
        }

        if (StrEqual(sInfo, "type"))
        {
            g_eInfo[client].iType++;

            g_eInfo[client].iType %= sizeof(g_sZoneTypes);
        }

        if (StrEqual(sInfo, "start"))
        {
            OpenPointsMenu(client);
            return 0;
        }

        if (StrEqual(sInfo, "confirm"))
        {
            ClearTimer(g_eInfo[client].hRenderGridSnap);
            g_eInfo[client].bFinishedCreatingZone = false;

            CreatePermanentZone(client);
            DB_SaveZone(client, FindZoneIndex(g_eInfo[client].iTrack, g_eInfo[client].iType));

            return 0;
        }

        OpenCreateZoneMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        ClearTimer(g_eInfo[client].hRenderGridSnap);
        OpenZoneParentMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_SpecifyPoints(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        if (StrEqual(sInfo, "snap"))
        {
            g_eInfo[client].iSnapSize *= 2;
            
            if (g_eInfo[client].iSnapSize > 64)
            {
                g_eInfo[client].iSnapSize = 8;
            }
        }

        if (StrEqual(sInfo, "style"))
        {
            g_eInfo[client].iEditStyle++;

            g_eInfo[client].iEditStyle %= 2;
        }

        if (StrEqual(sInfo, "start"))
        {
            g_fSetPoints[client][0] = g_fSnapPoint[client];

            g_eInfo[client].bIsCreatingZone = true;
            g_eInfo[client].bFinishedCreatingZone = false;
        }

        if (StrEqual(sInfo, "end"))
        {
            g_fSetPoints[client][1] = g_fSnapPoint[client];

            g_eInfo[client].bIsCreatingZone       = false;
            g_eInfo[client].bFinishedCreatingZone = true;
        }

        if (StrEqual(sInfo, "height"))
        {
            g_eInfo[client].bEditingHeight = true;
        }

        if (StrEqual(sInfo, "setheight"))
        {
            g_eInfo[client].bEditingHeight = false;
        }
        
        OpenPointsMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        OpenCreateZoneMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_RemoveZone(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        if (StrEqual(sInfo, "allmain"))
        {
            OpenConfirmMenu(client, Track_Main);
        }
        else if (StrEqual(sInfo, "allbonus"))
        {
            OpenConfirmMenu(client, Track_Bonus);
        }
        else
        {
            int iZone = StringToInt(sInfo);

            /**
             * Set the editing zone to the one being deleted, since
             * SourceMod doesn't allow passing data through a MenuHandler.
             */

            g_eInfo[client].iTrack = g_eZones[iZone].iTrack;
            g_eInfo[client].iType  = g_eZones[iZone].iType;

            OpenConfirmMenu(client, INVALID_TRACK);
        }
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        OpenZoneParentMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int MenuHandler_ConfirmDeletion(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[16];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        if (StrEqual(sInfo, "yesmain"))
        {
            RemoveZonePermanent(client, Track_Main);
        }

        if (StrEqual(sInfo, "yesbonus"))
        {
            RemoveZonePermanent(client, Track_Bonus);
        }

        if (StrEqual(sInfo, "yes"))
        {
            RemoveZonePermanent(client, INVALID_TRACK);
        }
        
        if (StrEqual(sInfo, "no"))
        {
            OpenRemoveZoneMenu(client);
            return 0;
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void OpenZoneParentMenu(int client)
{
    bool bEnabled = false;

    Menu hMenu = new Menu(MenuHandler_ZoneParent);

    hMenu.SetTitle("Zone Menu");

    hMenu.AddItem("create", "Create zone");

    /**
     * Loop through all zones, and if any are valid show
     * remove/edit menu.
     */

    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_eZones[i].bValid)
        {
            bEnabled = true;
            break;
        }
    }

    if (bEnabled)
    {
        hMenu.AddItem("remove", "Remove zones");
        hMenu.AddItem("edit",   "Edit zones");
    }
    else
    {
        hMenu.AddItem("remove", "Remove zones", ITEMDRAW_DISABLED);
        hMenu.AddItem("edit",   "Edit zones", ITEMDRAW_DISABLED);
    }

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenCreateZoneMenu(int client)
{
    if (g_eInfo[client].hRenderGridSnap == null)
    {
        g_eInfo[client].hRenderGridSnap = CreateTimer(0.1, DrawZoneLoop, client, TIMER_REPEAT);
    }

    char sTrack[16];
    char sType[64];

    Format(sTrack, sizeof(sTrack), "Track: %s",   g_sTracks[g_eInfo[client].iTrack]);
    Format(sType,  sizeof(sType),  "Type: %s\n ", g_sZoneTypes[g_eInfo[client].iType]);

    Menu hMenu = new Menu(MenuHandler_CreateZone);

    hMenu.SetTitle("Create Zone");

    hMenu.AddItem("track", sTrack);
    hMenu.AddItem("type",  sType);

    hMenu.AddItem("start", "Specify Points\n ");

    if (g_eInfo[client].bFinishedCreatingZone)
    {
        hMenu.AddItem("confirm", "Confirm");
    }
    else
    {
        hMenu.AddItem("confirm", "Confirm", ITEMDRAW_DISABLED);
    }

    hMenu.ExitBackButton = true;
    hMenu.ExitButton     = false;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenRemoveZoneMenu(int client)
{
    char sTitle[64];
    char sInfo[3];

    Menu hMenu = new Menu(MenuHandler_RemoveZone);

    hMenu.SetTitle("Remove Zones");

    hMenu.AddItem("allmain", "Remove all [Main] zones");
    hMenu.AddItem("allbonus", "Remove all [Bonus] zones\n ");

    for (int i = 0; i < MAXZONES; i++)
    {
        if (g_eZones[i].bValid)
        {
            Format(sTitle, sizeof(sTitle), "#%i - [%s] %s", i, g_sTracks[g_eZones[i].iTrack], g_sZoneTypes[g_eZones[i].iType]);
            Format(sInfo, sizeof(sInfo), "%i", i);
            hMenu.AddItem(sInfo, sTitle);
        }
    }

    hMenu.Pagination = true;
    hMenu.ExitBackButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenConfirmMenu(int client, int track)
{
    char sTitle[64];

    Menu hMenu = new Menu(MenuHandler_ConfirmDeletion);

    if (track == INVALID_TRACK)
    {
        Format(sTitle, sizeof(sTitle), "Confirm deletion of\n'[%s] %s'?", g_sTracks[g_eInfo[client].iTrack], g_sZoneTypes[g_eInfo[client].iType]);

        hMenu.SetTitle(sTitle);

        hMenu.AddItem("yes", "Yes");
        hMenu.AddItem("no", "No");
    }
    else
    {
        Format(sTitle, sizeof(sTitle), "Confirm deletion of all '[%s]' zones?", g_sTracks[track]);

        hMenu.SetTitle(sTitle);
        
        hMenu.AddItem((track == Track_Main) ? "yesmain" : "yesbonus", "Yes");
        hMenu.AddItem("no", "No");
    }

    hMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenPointsMenu(int client)
{
    char sTitle[64];
    char sSnapSize[16];
    char sEditStyle[32];

    Menu hMenu = new Menu(MenuHandler_SpecifyPoints);

    Format(sTitle,     sizeof(sTitle),     "Specify Points for\n'[%s] %s':", g_sTracks[g_eInfo[client].iTrack], g_sZoneTypes[g_eInfo[client].iType]);
    Format(sSnapSize,  sizeof(sSnapSize),  "Snap Size: %i", g_eInfo[client].iSnapSize);
    Format(sEditStyle, sizeof(sEditStyle), "Style: %s\n ", g_sEditStyles[g_eInfo[client].iEditStyle]);

    hMenu.SetTitle(sTitle);

    if (!g_eInfo[client].bIsCreatingZone)
    {
        hMenu.AddItem("start", "Set Start Point\n ");
    }
    else
    {
        hMenu.AddItem("end", "Set End Point\n ");
    }

    hMenu.AddItem("snap", sSnapSize);
    hMenu.AddItem("style", sEditStyle);

    if (g_eInfo[client].bEditingHeight)
    {
        hMenu.AddItem("setheight", "Set Height");
    }
    else
    {
        hMenu.AddItem("height", "Adjust Height");
    }

    hMenu.ExitBackButton = true;
    hMenu.ExitButton = false;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

//=================================
// Commands
//=================================

public Action CMD_Zone(int client, int args)
{
    OpenZoneParentMenu(client);

    return Plugin_Handled;
}

public Action CMD_Main(int client, int args)
{
    if (FindZoneIndex(Track_Main, Zone_Start) == -1)
    {
        PrintToChat(client, "%s\x08 No zone exists for \x01[\x05Main\x08, \x05Start\x01]\x08.", g_sPrefix);
        return Plugin_Handled;
    }

    int iPreviousTrack = g_eInfo[client].iCurrentTrack;

    g_eInfo[client].iCurrentTrack = Track_Main;

    /**
     * Call change track forward if the player changes zones.
     */

    if (iPreviousTrack != g_eInfo[client].iCurrentTrack)
    {
        Call_StartForward(g_hTrackChangeForward);

        Call_PushCell(client);
        Call_PushCell(Track_Main);

        Call_Finish();
    }

    CMD_Restart(client, 0);

    return Plugin_Handled;
}

public Action CMD_Bonus(int client, int args)
{
    if (FindZoneIndex(Track_Bonus, Zone_Start) == -1)
    {
        PrintToChat(client, "%s\x08 No zone exists for \x01[\x05Bonus\x08, \x05Start\x01]\x08.", g_sPrefix);
        return Plugin_Handled;
    }

    int iPreviousTrack = g_eInfo[client].iCurrentTrack;

    g_eInfo[client].iCurrentTrack = Track_Bonus;

    /**
     * Call change track forward if the player changes zones.
     */

    if (iPreviousTrack != g_eInfo[client].iCurrentTrack)
    {
        Call_StartForward(g_hTrackChangeForward);

        Call_PushCell(client);
        Call_PushCell(Track_Bonus);

        Call_Finish();
    }

    CMD_Restart(client, 0);

    return Plugin_Handled;
}

public Action CMD_End(int client, int args)
{
    int iZone = FindZoneIndex(g_eInfo[client].iCurrentTrack, Zone_End);

    if (iZone == -1)
    {
        PrintToChat(client, "%s\x08 No zone exists for \x01[\x05%s\x08, \x05End\x01]\x08.", g_sPrefix, g_sTracks[g_eInfo[client].iCurrentTrack]);
        return Plugin_Handled;
    }

    TeleportEntity(client, g_fZoneOrigin[iZone], NULL_VECTOR, NULL_VECTOR);

    return Plugin_Handled;
}

public Action CMD_Restart(int client, int args)
{
    int iZone = FindZoneIndex(g_eInfo[client].iCurrentTrack, Zone_Start);

    if (iZone == -1 || !g_eZones[iZone].bValid)
    {
        PrintToChat(client, "%s\x08 No zone exists for \x01[\x05%s\x08, \x05Start\x01]\x08.", g_sPrefix, g_sTracks[g_eInfo[client].iCurrentTrack]);
        return Plugin_Handled;
    }

    TeleportEntity(client, g_fZoneOrigin[FindZoneIndex(g_eInfo[client].iCurrentTrack, Zone_Start)], NULL_VECTOR, {0.0, 0.0, 0.0});

    return Plugin_Handled;
}

public int Native_GetZoneOrigin(Handle plugin, int param)
{
    SetNativeArray(3, g_fZoneOrigin[GetNativeCell(1)][GetNativeCell(2)], 3);
}
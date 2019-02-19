#include <globaltimer>

#include <clientprefs>
#include <sourcemod>

enum struct HudSettings
{
    bool bShowRunStats;
    bool bShowSR;
};

enum struct HudInfo
{
    bool   bShowRunStats;

    int    iStyle;
    int    iTrack;

    float  fSpeed;
    float  fPrevSpeed;

    char   sStyleName[64];

    RunStats    eStats;
    HudSettings eSettings;

    Handle hUpdateHud;
    Handle hShowRunStats;
};

HudInfo g_eHud[MAXPLAYERS + 1];

char g_sMessage[MAXPLAYERS + 1][512];

bool g_bLate;

float g_fPb[MAXPLAYERS + 1][MAXSTYLES][2];
char  g_sPb[MAXPLAYERS + 1][MAXSTYLES][2][16];
float g_fSr[MAXSTYLES][2];

char g_sMapName[128];

Handle g_hShowStatsCookie; // Show run stats after completing map. (Defaulted to on)
Handle g_hStats_ShowSR;    // Show ΔSR instead of ΔPB on run stats.

ConVar g_cvHideMoney;

public Plugin myinfo = 
{
    name        = "[GlobalTimer] Hud",
    description = "Hud support for timer.",
    author      = "Connor",
    version     = VERSION,
    url         = URL
};

public void OnPluginStart()
{
    g_hShowStatsCookie = RegClientCookie("gt_showrunstats", "Show stats after completing map.",      CookieAccess_Private);
    g_hStats_ShowSR    = RegClientCookie("gt_stats_showsr", "Show ΔSR instead of ΔPB on run stats.", CookieAccess_Private);

    SetCookieMenuItem(HudCookieHandler, 0, "Hud Settings");

    HookEvent("player_connect_full", OnPlayerFullyConnected);

    g_cvHideMoney = FindConVar("mp_maxmoney");

    if (g_bLate)
    {
        for (int client = 1; client < MAXPLAYERS; client++)
        {
            if (!IsPlayer(client))
            {
                continue;
            }

            OnClientPostAdminCheck(client);

            g_eHud[client].hUpdateHud = CreateTimer(0.1, UpdateHud, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

            if (!AreClientCookiesCached(client))
            {
                continue;
            }
            
            OnClientCookiesCached(client);
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
}

public void OnClientPostAdminCheck(int client)
{
    strcopy(g_eHud[client].sStyleName, 64, "Auto");

    for (int style = 0; style < MAXSTYLES; style++)
    {
        for (int track = 0; track <= 1; track++)
        {
            g_fPb[client][style][track] = 0.0;
            Format(g_sPb[client][style][track], 16, "N/A\t\t");
        }
    }
}

public void OnPlayerFullyConnected(Event event, const char[] name, bool broadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    ChangeClientTeam(client, GetRandomInt(2, 3));
    g_eHud[client].hUpdateHud = CreateTimer(0.1, UpdateHud, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    // Hiding radar + cash
    SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | 1<<12);  
    SendConVarValue(client, g_cvHideMoney, "0");
}

public void OnSrLoaded(float time, RunDBInfo info)
{
    g_fSr[info.iStyle][info.iTrack] = time;
}

public void OnPbLoaded(int client, int style, int track, float time)
{
    g_fPb[client][style][track] = time;
    FormatSeconds(time, g_sPb[client][style][track], 16, Accuracy_Med, false, false);
}

public void OnClientCookiesCached(int client)
{
    char sCookie[2];

    GetClientCookie(client, g_hShowStatsCookie, sCookie, sizeof(sCookie));
    g_eHud[client].eSettings.bShowRunStats = view_as<bool>(StringToInt(sCookie));

    GetClientCookie(client, g_hStats_ShowSR, sCookie, sizeof(sCookie));
    g_eHud[client].eSettings.bShowSR = view_as<bool>(StringToInt(sCookie));
}

public void OnClientDisconnect(int client)
{
    ClearTimer(g_eHud[client].hUpdateHud);
    ClearTimer(g_eHud[client].hShowRunStats);
}

public void OnPlayerBeatSr(int client, int style, int track, float newtime, float oldtime)
{
    g_fSr[style][track] = newtime;
}

public void OnPlayerBeatPb(int client, RunStats stats, float oldpb)
{
    if (g_eHud[client].eSettings.bShowRunStats)
    {
        g_eHud[client].bShowRunStats = true;
    }

    g_fPb[client][stats.iStyle][stats.iTrack] = stats.fTime;
    FormatSeconds(stats.fTime, g_sPb[client][stats.iStyle][stats.iTrack], 16, Accuracy_Med, false, false);

    GetStats(client, stats);
}

public void OnPlayerTrackChange(int client, int track)
{
    g_eHud[client].iTrack = track;
}

public void OnPlayerStyleChange(int client, Style settings)
{
    g_eHud[client].iStyle = settings.iIndex;
    strcopy(g_eHud[client].sStyleName, 64, settings.sName);

    for (int track = 0; track <= 1; track++)
    {
        g_fPb[client][settings.iIndex][track] = GetPlayerPb(client, settings.iIndex, track);
    }
}

public void OnPlayerEnterZone(int client, int tick, int track, int type)
{
    if (track == g_eHud[client].iTrack && type == Zone_Start)
    {
        ClearTimer(g_eHud[client].hShowRunStats);
        g_eHud[client].hShowRunStats = CreateTimer(3.0, ShowRunStats, client);
    }
}

public void OnPlayerFinishedTrack(int client, RunStats stats, float pb)
{
    if (g_eHud[client].eSettings.bShowRunStats)
    {
        g_eHud[client].bShowRunStats = true;
    }

    GetStats(client, stats);
}

//=================================
// Menus
//=================================

public void HudCookieHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlength)
{
    if (action == CookieMenuAction_SelectOption)
    {
        OpenHudCookieMenu(client);
    }
}

int MenuHandler_HudCookies(Menu menu, MenuAction action, int client, int index)
{
    if (action == MenuAction_Select)
    {
        char sInfo[10];

        if (!menu.GetItem(index, sInfo, sizeof(sInfo)))
        {
            return 0;
        }

        if (StrEqual(sInfo, "showstats"))
        {
            g_eHud[client].eSettings.bShowRunStats = !g_eHud[client].eSettings.bShowRunStats;

            char sSetting[2];
            
            Format(sSetting, sizeof(sSetting), "%b", g_eHud[client].eSettings.bShowRunStats);
            SetClientCookie(client, g_hShowStatsCookie, sSetting);
        }

        if (StrEqual(sInfo, "sr"))
        {
            g_eHud[client].eSettings.bShowSR = !g_eHud[client].eSettings.bShowSR;

            char sSetting[2];
            
            Format(sSetting, sizeof(sSetting), "%b", g_eHud[client].eSettings.bShowSR);
            SetClientCookie(client, g_hStats_ShowSR, sSetting);
        }

        OpenHudCookieMenu(client);
    }
    else if (action == MenuAction_Cancel && index == MenuCancel_ExitBack)
    {
        ShowCookieMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void OpenHudCookieMenu(int client)
{
    Menu hMenu = new Menu(MenuHandler_HudCookies);

    hMenu.SetTitle("Hud Settings");

    if (g_eHud[client].eSettings.bShowRunStats)
    {
        hMenu.AddItem("showstats", "[✔] Show post-run stats");
    }
    else
    {
        hMenu.AddItem("showstats", "[   ] Show post-run stats");
    }

    if (g_eHud[client].eSettings.bShowSR)
    {
        hMenu.AddItem("sr", "  - [✔] Show ΔSR instead of ΔPB", g_eHud[client].eSettings.bShowRunStats ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }
    else
    {
        hMenu.AddItem("sr", "  - [   ] Show ΔSR instead of ΔPB", g_eHud[client].eSettings.bShowRunStats ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    hMenu.ExitBackButton = true;

    hMenu.Display(client, MENU_TIME_FOREVER);
}

//=================================
// Other
//=================================

void GetStats(int client, RunStats stats)
{
    g_eHud[client].eStats.fTime  = stats.fTime;
    g_eHud[client].eStats.fDifPb = stats.fDifPb;
    g_eHud[client].eStats.fDifSr = stats.fDifSr;
    g_eHud[client].eStats.iTrack = stats.iTrack;
    g_eHud[client].eStats.iJumps = stats.iJumps;
    g_eHud[client].eStats.fSSJ   = stats.fSSJ;
    g_eHud[client].eStats.fMaxSpeed = stats.fMaxSpeed;
}

//=================================
// Timers
//=================================

public Action ShowRunStats(Handle timer, int client)
{
    g_eHud[client].bShowRunStats = false;
    g_eHud[client].hShowRunStats = null;
}

public Action UpdateHud(Handle timer, int client)
{
    int target = client;

    decl String:sTime[16];

    if (!IsPlayerAlive(client))
    {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
    }

    if (g_eHud[target].bShowRunStats)
    {
        decl String:sDif[64], String:sDifTime[12], String:sSSJ[8], String:sDifColor[8], String:sJumps[4];
        bool bFirst;

        FormatSeconds(g_eHud[target].eStats.fTime, sTime, sizeof(sTime), Accuracy_High, false, false);

        if (g_eHud[client].eSettings.bShowSR)
        {
            if (g_eHud[target].eStats.fDifSr < 0.0)
            {
                Format(sDifColor, sizeof(sDifColor), "#43f441");
            }
            else
            {
                Format(sDifColor, sizeof(sDifColor), "#f44141");
            }
        }
        else
        {
            if (g_eHud[target].eStats.fDifPb < 0.0)
            {
                Format(sDifColor, sizeof(sDifColor), "#43f441");
            }
            else
            {
                Format(sDifColor, sizeof(sDifColor), "#f44141");
            }
        }

        if (g_eHud[client].eSettings.bShowSR)
        {
            if (g_eHud[target].eStats.fTime == g_eHud[target].eStats.fDifSr)
            {
                Format(sDif, sizeof(sDif), "ΔSR: <font color='#43f441'>First completion</font>");
            }
            else
            {
                FormatSeconds(g_eHud[target].eStats.fDifSr, sDifTime, sizeof(sDifTime), Accuracy_High, true, true);
                Format(sDif, sizeof(sDif), "ΔSR: \t(<font color='%s'>%s</font>)", sDifColor, sDifTime);
            }
        }
        else
        {
            if (g_eHud[target].eStats.fTime == g_eHud[target].eStats.fDifPb)
            {
                Format(sDif, sizeof(sDif), "ΔPB: <font color='#43f441'>First completion</font>");
            }
            else
            {
                FormatSeconds(g_eHud[target].eStats.fDifPb, sDifTime, sizeof(sDifTime), Accuracy_High, true, true);
                Format(sDif, sizeof(sDif), "ΔPB: \t(<font color='%s'>%s</font>)", sDifColor, sDifTime);
            }
        }

        if (g_eHud[target].eStats.fSSJ == 0.0)
        {
            Format(sSSJ, sizeof(sSSJ), "N/A");
        }
        else
        {
            Format(sSSJ, sizeof(sSSJ), "%.2f", g_eHud[target].eStats.fSSJ);
        }

        Format(sJumps, sizeof(sJumps), "%i", g_eHud[target].eStats.iJumps);

        Format(g_sMessage[client], 512,
        "<pre><span class='fontSize-m'>\
        <font color='#f4d941'>Run Stats: %s - %s</font><br>\
            Time: \t%s<br>\
            %s<br><br>\
            Jumps: %s\t\t\tSSJ: %s\
        </span></pre>",
        g_sMapName, g_sTracks[g_eHud[target].eStats.iTrack], sTime, sDif, sJumps, sSSJ);
    }
    else
    {
        decl String:sTopRow[128], String:sTimeColor[8], String:sJumps[12], String:sSpeed[36], String:sSync[12], String:sPlacement[20];
        float fVel[3];

        if (IsPlayerInRun(target))
        {
            RunFrame frame;
            GetPlayerFrame(target, frame);

            if (frame.fTime < g_fSr[frame.iStyle][frame.iTrack] || g_fSr[frame.iStyle][frame.iTrack] == 0.0)
            {
                Format(sTimeColor, sizeof(sTimeColor), "#4cf441");
            }
            else if (frame.fTime < GetPlayerPb(target, frame.iStyle, frame.iTrack) || GetPlayerPb(target, frame.iStyle, frame.iTrack) == 0.0)
            {
                Format(sTimeColor, sizeof(sTimeColor), "#f4eb41");
            }
            else
            {
                Format(sTimeColor, sizeof(sTimeColor), "#f44141");
            }

            FormatSeconds(frame.fTime, sTime, sizeof(sTime), Accuracy_Low, false, false);

            Format(sJumps, sizeof(sJumps), "%i [%.1f]", frame.iJumps, GetPlayerJumpSpeed(target));
            Format(sSync, sizeof(sSync), "%.2f", frame.fSync);

            if (strlen(sJumps) < 10)
            {
                StrCat(sJumps, sizeof(sJumps), "\t");
            }

            Format(sPlacement, sizeof(sPlacement), "%i/%i", GetPlacementByTime(frame.fTime, frame.iStyle, frame.iTrack), GetTotalTimes(frame.iStyle, frame.iTrack));

            Format(sTopRow, sizeof(sTopRow), "\tTime: <font color='%s'>%s</font>\t\tStyle: %s%s<br>", sTimeColor, sTime, g_eHud[target].sStyleName,
                (strlen(g_eHud[target].sStyleName) <= 6) ? "\t\t" : (strlen(g_eHud[target].sStyleName) >= 10) ? "" : "\t");
        }
        else
        {
            Format(sTimeColor, sizeof(sTimeColor), "#f44141");
            Format(sJumps, sizeof(sJumps), "0\t\t\t");
            Format(sSync, sizeof(sSync), "N/A");

            int iPlacement = GetPlacementByTime(g_fPb[target][g_eHud[target].iStyle][g_eHud[target].iTrack], g_eHud[target].iStyle, g_eHud[target].iTrack);

            if (iPlacement == 0)
            {
                Format(sPlacement, sizeof(sPlacement), "-/%i", GetTotalTimes(g_eHud[target].iStyle, g_eHud[target].iTrack));
            }
            else
            {
                Format(sPlacement, sizeof(sPlacement), "%i/%i", iPlacement - 1, GetTotalTimes(g_eHud[target].iStyle, g_eHud[target].iTrack) - 1);
            }

            if (g_fSr[g_eHud[target].iStyle][g_eHud[target].iTrack] == 0.0)
            {
                Format(sTime, sizeof(sTime), "N/A\t\t");
            }
            else
            {
                FormatSeconds(g_fSr[g_eHud[target].iStyle][g_eHud[target].iTrack], sTime, sizeof(sTime), Accuracy_Med, false, false);
            }

            Format(sTopRow, sizeof(sTopRow), "\tSR: <font color='#43f441'>%s</font>\t\tStyle: %s%s<br>", sTime, g_eHud[target].sStyleName,
                (strlen(g_eHud[target].sStyleName) <= 6) ? "\t\t" : (strlen(g_eHud[target].sStyleName) >= 10) ? "" : "\t");
        }

        GetEntPropVector(target, Prop_Data, "m_vecVelocity", fVel);
        fVel[2] = 0.0;

        g_eHud[target].fSpeed = GetVectorLength(fVel);

        if (g_eHud[target].fSpeed <= g_eHud[target].fPrevSpeed)
        {
            Format(sSpeed, sizeof(sSpeed), "<font color='#f4ac41'>%.0f</font>", g_eHud[target].fSpeed);
        }
        else
        {
            Format(sSpeed, sizeof(sSpeed), "<font color='#79f441'>%.0f</font>", g_eHud[target].fSpeed);
        }

        Format(g_sMessage[client], 512,
        "<pre>\
        <span class='fontSize-m'>\
            %s\
            \tPB: %s\t\tRank: %s<br><br>\
            \tJumps: %s\tSpeed: %s<br>\
            \tSync: %s\
        </pre>",
        sTopRow, g_sPb[target][g_eHud[target].iStyle][g_eHud[target].iTrack], sPlacement, sJumps, sSpeed, sSync);
    }

    g_eHud[target].fPrevSpeed = g_eHud[target].fSpeed;

    PrintHintText(client, g_sMessage[client]);
}
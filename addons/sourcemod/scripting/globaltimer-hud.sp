#include <globaltimer>

#include <sourcemod>

Handle g_hHudUpdate[MAXPLAYERS + 1];

char g_sHudText[MAXPLAYERS + 1][512];

bool g_bLate;

char g_sTimeColor[2][6] =
{
    "#f44341", // Timer stopped
    "#56f441"  // Timer running
};

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
    if (g_bLate)
    {
        for (int i = 1; i < MAXPLAYERS; i++)
        {
            if (IsClientInGame(i))
            {
                OnClientPostAdminCheck(i);
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_bLate = late;

    return APLRes_Success;
}

public void OnClientPostAdminCheck(int client)
{
    g_hHudUpdate[client] = CreateTimer(0.1, UpdateHudLoop, client, TIMER_REPEAT);
}

public void OnClientDisconnect(int client)
{
    ClearTimer(g_hHudUpdate[client]);
}

public Action UpdateHudLoop(Handle timer, int client)
{
    int target = client;

    char sTime[16], sPb[16], sSpeed[7], sJumps[12];
    float fVel[3];
    
    if (!IsPlayerAlive(client))
    {
        // target = spectated player
    }

    if (IsPlayerInRun(target))
    {
        FormatSeconds(GetPlayerTime(target), sTime, sizeof(sTime), Accuracy_Low);
    }
    else
    {
        Format(sTime, sizeof(sTime), "Stopped");
    }

    if (GetPlayerPb(target, GetPlayerTrack(target)) != 0.0)
    {
        FormatSeconds(GetPlayerPb(target, GetPlayerTrack(target)), sPb, sizeof(sPb), Accuracy_Med);
    }
        
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);
    fVel[2] = 0.0;

    float fSpeed = GetVectorLength(fVel);

    Format(sSpeed, sizeof(sSpeed), "%.1f", fSpeed);
    Format(sJumps, sizeof(sJumps), "%i [%.0f]", GetPlayerJumpCount(target), GetPlayerJumpSpeed(target));

    Format(g_sHudText[target], 512,
    "<pre>\
    <span class='fontSize-m'>\
    \
        \tTime: <font color='%s'>%s\t<font color='#ffffff'>Speed: %s\t<br>\
        \t<font color='#ffffff'>Best: %s\tJumps: %s\t\
    \
    </span>\
    </pre>",
    g_sTimeColor[IsPlayerInRun(target)], sTime, sSpeed, sPb, sJumps);

    PrintHintText(client, g_sHudText[target]);
}
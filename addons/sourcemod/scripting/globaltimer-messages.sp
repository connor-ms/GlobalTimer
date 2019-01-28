#include <globaltimer>

#include <sourcemod>

enum struct PlayerStrings
{
    char sName[64];
    char sOldPb[32];
    char sPb[32];
    char sTime[32];
    char sDif[32];
}

PlayerStrings g_ePlayerStrings[MAXPLAYERS + 1];

char g_sTrackNames[2][64] = 
{
    "Main",
    "Bonus"
};

char g_sBeatSrMessage[512];
char g_sBeatPbMessage[512];
char g_sFirstPbMessage[512];
char g_sFinishMapMessage[512];

public Plugin myinfo = 
{
    name = "[GlobalTimer] Messages",
    author = "Connor",
    description = "Message handling for timer.",
    version = VERSION,
    url = URL
};

public void OnPluginStart()
{
    RegAdminCmd("sm_reloadmessages", CMD_ReloadMessages, ADMFLAG_CONFIG, "Reloads messages config.");

    GetAllVariables();
}

//=================================
// Forwards
//=================================

public void OnPlayerBeatSr(int client, int track, float newtime, float oldtime)
{
    char sMessage[512];

    FillPlayerStrings(client, newtime, newtime, oldtime);

    FormatMessage(client, g_sBeatSrMessage, sMessage, sizeof(sMessage));

    PrintToChatAll("%s", sMessage);
}

public void OnPlayerBeatPb(int client, int track, float newtime, float oldtime)
{
    char sMessage[512];

    FillPlayerStrings(client, newtime, newtime, oldtime);

    /**
     * If there is no previous time, display special message for it.
     * Otherwise, display normal message for beating pb.
    */

    if (oldtime == 0.0)
    {
        FormatMessage(client, g_sFirstPbMessage, sMessage, sizeof(sMessage));
    }
    else
    {
        FormatMessage(client, g_sBeatPbMessage, sMessage, sizeof(sMessage));
    }

    PrintToChatAll("%s", sMessage);
}

public void OnPlayerFinishedTrack(int client, int track, float time, float pb)
{
    char sMessage[512];

    FillPlayerStrings(client, time, pb);

    FormatMessage(client, g_sFinishMapMessage, sMessage, sizeof(sMessage));

    PrintToChatAll("%s", sMessage);
}

//=================================
// Other
//=================================

void FillPlayerStrings(int client, float time, float pb, float oldpb = 0.0)
{
    float fDif;

    /**
     * If the player didn't beat their pb, use the difference between pb and the most recent time.
     *
     * If they did beat their pb, both time and pb will be the same, so use oldpb to
     * find the difference.
    */

    if (oldpb == 0.0)
    {
        fDif = time - pb;
    }
    else
    {
        fDif = oldpb - time;
    }

    GetClientName(client, g_ePlayerStrings[client].sName, 64);

    FormatSeconds(time,  g_ePlayerStrings[client].sTime,  32, true);
    FormatSeconds(pb,    g_ePlayerStrings[client].sPb,    32, true);
    FormatSeconds(fDif,  g_ePlayerStrings[client].sDif,   32, true);
    FormatSeconds(oldpb, g_ePlayerStrings[client].sOldPb, 32, true);
}

bool GetCustomMessage(const char[] type, char[] result, int size, const char[] value = "message")
{
    char sPath[128];

    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/GlobalTimer/messages.cfg");

    KeyValues kv = new KeyValues("Messages");
    kv.ImportFromFile(sPath);

    if (!kv.JumpToKey(type))
    {
        delete kv;
        return false;
    }

    kv.GetString(value, result, size);

    delete kv;
    return true;
}

void FormatMessage(int client, char[] template, char[] message, int size)
{
    /**
     * Copy the template string to the string that will be modified (otherwise
     * the message will only work once, since after that all the variables
     * will be replaced already)
    */

    strcopy(message, size, template);

    /**
     * First replace all the variables.
     * Yeah this is pretty ghetto but it works ¯\_(ツ)_/¯
    */

    ReplaceString(message, size, "{prefix}",  g_sPrefix,                             false);
    ReplaceString(message, size, "{name}",    g_ePlayerStrings[client].sName,        false);
    ReplaceString(message, size, "{time}",    g_ePlayerStrings[client].sTime,        false);
    ReplaceString(message, size, "{pb}",      g_ePlayerStrings[client].sPb,          false);
    ReplaceString(message, size, "{oldpb}",   g_ePlayerStrings[client].sOldPb,       false);
    ReplaceString(message, size, "{dif}",     g_ePlayerStrings[client].sDif,         false);
    ReplaceString(message, size, "{track}",   g_sTrackNames[GetPlayerTrack(client)], false);
    
    /**
     * Then replace color aliases with "correct" colors.
    */

    FormatColors(message, size);
}

bool GetAllVariables()
{
    bool bSuccess;

    /**
     * If anything fails, bSuccess will be set to false, showing something failed.
     * No way to check what failed though lol sucks for whoever has to deal with that
    */

    /**
     * Find custom variables.
    */

    bSuccess = GetCustomMessage("variables", g_sPrefix, sizeof(g_sPrefix), "{prefix}");
    FormatColors(g_sPrefix, sizeof(g_sPrefix));

    bSuccess = GetCustomMessage("variables", g_sTrackNames[Track_Main],  64, "main");
    bSuccess = GetCustomMessage("variables", g_sTrackNames[Track_Bonus], 64, "bonus");

    /**
     * Find custom messages for each event.
    */

    bSuccess = GetCustomMessage("sr",      g_sBeatSrMessage,    sizeof(g_sBeatSrMessage));
    bSuccess = GetCustomMessage("pb",      g_sBeatPbMessage,    sizeof(g_sBeatPbMessage));
    bSuccess = GetCustomMessage("firstpb", g_sFirstPbMessage,   sizeof(g_sFirstPbMessage));
    bSuccess = GetCustomMessage("finish",  g_sFinishMapMessage, sizeof(g_sFinishMapMessage));

    return bSuccess;
}

//=================================
// Commands
//=================================

public Action CMD_ReloadMessages(int client, int args)
{
    /**
     * Refreshes the template strings.
    */

    if (GetAllVariables())
    {
        PrintToChat(client, "%s Successfully reloaded messages.", g_sPrefix);

        return Plugin_Handled;
    }

    PrintToChat(client, "%s One or more messages failed to reload.", g_sPrefix);

    return Plugin_Handled;
}
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

PlayerStrings g_ePlayerStrings[MAXPLAYERS + 1][2];

char g_sTrackNames[2][64] = 
{
    "Main",
    "Bonus"
};

char g_sBeatSrTemplate[512];
char g_sBeatPbTemplate[512];
char g_sFirstPbTemplate[512];
char g_sFinishMapTemplate[512];

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

public void OnPlayerBeatSr(int client, int style, int track, float newtime, float oldtime)
{
    char sMessage[512];

    FillPlayerStrings(client, newtime, oldtime, Accuracy_Med, 0);

    FormatMessage(client, g_sBeatSrTemplate, sMessage, sizeof(sMessage), 0);

    PrintToChatAll("%s", sMessage);
    PrintToConsoleAll("\n%s", sMessage);
}

public void OnPlayerBeatPb(int client, RunStats stats, float oldpb)
{
    char sChatMessage[512];    // Chat uses medium accuracy to look cleaner.
    char sServerMessage[512];  // Console uses high accuracy so "advanced" users can see.

    FillPlayerStrings(client, stats.fTime, oldpb, Accuracy_Med,  0);
    FillPlayerStrings(client, stats.fTime, oldpb, Accuracy_High, 1);

    /**
     * If there is no previous time, display special message for it.
     * Otherwise, display normal message for beating pb.
     */

    if (oldpb == 0.0)
    {
        FormatMessage(client, g_sFirstPbTemplate, sChatMessage,   sizeof(sChatMessage),   0);
        FormatMessage(client, g_sFirstPbTemplate, sServerMessage, sizeof(sServerMessage), 1);
    }
    else
    {
        FormatMessage(client, g_sBeatPbTemplate, sChatMessage,   sizeof(sChatMessage),   0);
        FormatMessage(client, g_sBeatPbTemplate, sServerMessage, sizeof(sServerMessage), 1);
    }

    PrintToChatAll("%s", sChatMessage);
    PrintToConsoleAll("%s\n", sServerMessage);
    PrintToServer("\n%s\n", sServerMessage);
}

public void OnPlayerFinishedTrack(int client, RunStats stats, float pb)
{
    char sChatMessage[512];
    char sServerMessage[512];

    FillPlayerStrings(client, stats.fTime, pb, Accuracy_Med,  0);
    FillPlayerStrings(client, stats.fTime, pb, Accuracy_High, 1);

    FormatMessage(client, g_sFinishMapTemplate, sChatMessage,   sizeof(sChatMessage),   0);
    FormatMessage(client, g_sFinishMapTemplate, sServerMessage, sizeof(sServerMessage), 1);
    
    PrintToChat(client, "%s", sChatMessage);
    PrintToConsole(client, "%s", sServerMessage);
}

//=================================
// Other
//=================================

void FillPlayerStrings(int client, float time, float pb, int accuracy, int type, float oldpb = 0.0)
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
        fDif = FloatAbs(time - pb);
    }
    else
    {
        fDif = FloatAbs(oldpb - time);
    }

    GetClientName(client, g_ePlayerStrings[client][type].sName,  64);

    FormatSeconds(time,   g_ePlayerStrings[client][type].sTime,  32, accuracy, false, false);
    FormatSeconds(pb,     g_ePlayerStrings[client][type].sPb,    32, accuracy, false, false);
    FormatSeconds(fDif,   g_ePlayerStrings[client][type].sDif,   32, accuracy, false, false);
    FormatSeconds(oldpb,  g_ePlayerStrings[client][type].sOldPb, 32, accuracy, false, false);
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

void FormatMessage(int client, char[] template, char[] message, int size, int type)
{
    int  iRank,    iTotal;
    char sRank[5], sTotal[5];

    RunFrame eFrame;
    GetPlayerFrame(client, eFrame);

    Style eStyle;
    GetPlayerStyleSettings(client, eStyle);

    /**
     * Get info and setup last few needed strings.
     */

    iRank  = GetPlacementByTime(eFrame.fTime, eFrame.iStyle, eFrame.iTrack);
    iTotal = GetTotalTimes(eFrame.iStyle, eFrame.iTrack);

    IntToString(iRank,  sRank,  sizeof(sRank));
    IntToString(iTotal, sTotal, sizeof(sTotal));

    /**
     * Copy the template string to the string that will be modified (otherwise
     * the message will only work once, since after that all the variables
     * will be replaced already)
     */

    strcopy(message, size, template);

    /**
     * First replace all the variables.
     */

    ReplaceString(message, size, "{prefix}",  g_sPrefix,                             false);
    ReplaceString(message, size, "{name}",    g_ePlayerStrings[client][type].sName,  false);
    ReplaceString(message, size, "{time}",    g_ePlayerStrings[client][type].sTime,  false);
    ReplaceString(message, size, "{pb}",      g_ePlayerStrings[client][type].sPb,    false);
    ReplaceString(message, size, "{oldpb}",   g_ePlayerStrings[client][type].sOldPb, false);
    ReplaceString(message, size, "{dif}",     g_ePlayerStrings[client][type].sDif,   false);
    ReplaceString(message, size, "{track}",   g_sTrackNames[eFrame.iTrack],          false);
    ReplaceString(message, size, "{style}",   eStyle.sName,                          false);
    ReplaceString(message, size, "{rank}",    sRank,                                 false);
    ReplaceString(message, size, "{total}",   sTotal,                                false);

    /**
     * Then replace color aliases with "correct" colors if it's a chat message.
     * If it isn't, remove all color aliases.
     */
    
    if (type == 0)
    {
        FormatColors(message, size);
    }
    else
    {
        for (int i = 0; i < sizeof(g_sColors); i++)
        {
            ReplaceString(message, size, g_sColors[i][0], "", false);
        }
    }
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

    bSuccess = GetCustomMessage("sr",      g_sBeatSrTemplate,    sizeof(g_sBeatSrTemplate));
    bSuccess = GetCustomMessage("pb",      g_sBeatPbTemplate,    sizeof(g_sBeatPbTemplate));
    bSuccess = GetCustomMessage("firstpb", g_sFirstPbTemplate,   sizeof(g_sFirstPbTemplate));
    bSuccess = GetCustomMessage("finish",  g_sFinishMapTemplate, sizeof(g_sFinishMapTemplate));

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
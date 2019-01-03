#include <globaltimer>

#include <sourcemod>

public Plugin myinfo = 
{
    name = "[GlobalTimer] Messages",
    author = "Connor",
    description = "Message handling for timer.",
    version = VERSION,
    url = URL
};

/*
 * TODO: Read config file for custom messages.
*/

public void OnPlayerBeatSr(int client, int track, float oldtime, float newtime)
{
    char sName[64];

    GetClientName(client, sName, sizeof(sName));

    PrintToChatAll("%s \x05%s \x08has set a new \x07SERVER RECORD!", PREFIX, sName);
}

public void OnPlayerBeatPb(int client, int track, float oldtime, float newtime)
{
    char sName[64];
    char sNewTime[64];
    char sDelta[64];

    float fDelta = oldtime - newtime;

    GetClientName(client, sName, sizeof(sName));

    FormatSeconds(newtime, sNewTime, sizeof(sNewTime), true);
    FormatSeconds(fDelta, sDelta, sizeof(sDelta), true);

    if (oldtime == 0.0)
    {
        PrintToChatAll("%s \x05%s \x08finished the map in \x05%s.", PREFIX, sName, sNewTime);
    }
    else
    {
        PrintToChatAll("%s \x05%s \x08finished the map in \x05%s \x01(\x06-%s\x01)\x08.", PREFIX, sName, sNewTime, sDelta);
    }
}

public void OnPlayerFinishedTrack(int client, int track, float time, float pb)
{
    char sName[64];
    char sTime[64];
    char sPb[64];
    char sDelta[64];

    float fDelta = time - pb;

    GetClientName(client, sName, sizeof(sName));
    FormatSeconds(time, sTime, sizeof(sTime), true);
    FormatSeconds(pb, sPb, sizeof(sPb), true);
    FormatSeconds(fDelta, sDelta, sizeof(sDelta), true);

    PrintToChatAll("%s \x05%s \x08finished the map in \x05%s \x01(\x07+%s\x01)\x08.", PREFIX, sName, sTime, sDelta);
}
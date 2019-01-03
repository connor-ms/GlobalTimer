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

public void OnPlayerBeatSr(int client, int track, float oldtime, float newtime)
{
    PrintToChatAll("NEW RECORD!!!");
    PrintToChatAll("NEW RECORD!!!");
    PrintToChatAll("NEW RECORD!!!");
}

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

public void OnPlayerFinishedTrack(int client, int track, float time, float pb)
{
    char sName[64];
    char sTime[64];
    char sPb[64];

    GetClientName(client, sName, sizeof(sName));
    FormatSeconds(time, sTime, sizeof(sTime), true);
    FormatSeconds(pb, sPb, sizeof(sPb), true);

    PrintToChatAll("%s %s finished track %i in {red}%s {white}(pb: %s).", PREFIX, sName, track, sTime, sPb);
}
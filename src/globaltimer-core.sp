#include <globaltimer>

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = 
{
    name = "[GlobalTimer] Core",
    author = AUTHOR,
    description = "CS:GO bhop timer.",
    version = VERSION,
    url = URL
};

public void OnPluginStart()
{
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    
}

public void OnPlayerLeaveZone(int client, int tick, int track)
{
    PrintToChat(client, "Left at tick %i from track %i", tick, track);
}

public void OnPlayerEnterZone(int client, int tick, int track)
{
    PrintToChat(client, "Entered at tick %i from track %i", tick, track);
}
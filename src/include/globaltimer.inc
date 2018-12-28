#if defined _globaltimer_include_
    #endinput
#endif
#define _globaltimer_include_

#define VERSION "0.01a"
#define AUTHOR  "Connor"
#define URL     "www.steamcommunity.com/id/connorms"

/*
    Colors:
    White:       \x01
    Dark Red:    \x02
    Pink:        \x03
    Green:       \x04
    Yellow       \x05
    Light Green: \x06
    Red:         \x07
    Gray:        \x08
    Blue:        \x0B
    Dark Blue:   \x0C
    Purple:      \x0E
*/

#define PREFIX " \x01[\x0BGlobalTimer\x01]\x08"

enum
{
    Track_MainStart,
    Track_MainEnd,
    Track_BonusStart,
    Track_BonusEnd
};

forward void OnPlayerLeaveZone(int client, int tick, int track);
forward void OnPlayerEnterZone(int client, int tick, int track);
forward void OnPlayerTrackChange(int client);

native int IsPlayerInZone(int client);
native int GetPlayerTrack(int client);

stock float min(float num1, float num2)
{
    if (num1 < num2)
        return num1;
    else
        return num2;
}

stock float max(float num1, float num2)
{
    if (num1 > num2)
        return num1;
    else
        return num2;
}

stock float avg(float num1, float num2)
{
    return (num1 + num2) / 2.0;
}

stock float vecavg(float source[3], float vec1[3], float vec2[3])
{
    source[0] = avg(vec1[0], vec2[0]);
    source[1] = avg(vec1[1], vec2[1]);
    source[2] = avg(vec1[2], vec2[2]);
}

stock ClearTimer(&Handle:timer)
{
    if (timer != INVALID_HANDLE)
    {
        KillTimer(timer);
    }
    timer = INVALID_HANDLE;
}

stock bool IsValidClient(int client)
{
    return IsClientInGame(client) && IsClientConnected(client) && !IsFakeClient(client);
}

stock void DB_ErrorHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        PrintToServer("DB error! (%s)", error);
        return;
    }
}

stock void FormatSeconds(float time, char[] output, int outputsize)
{
    int   iHours;
    int   iMinutes;
    float iSeconds;

    iHours   = RoundToFloor(time / 3600);
    iMinutes = RoundToFloor((time - (iHours * 3600)) / 60);
    time    -= (iHours * 3600);
    time    -= (iMinutes * 60);
    iSeconds = RoundToFloor(time) + (time - RoundToFloor(time));

    if (iHours > 0)
    {
        Format(output, outputsize, "%s%i:%s%i:%s%.3f", (iHours < 10) ? "0" : "", iHours, (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10) ? "0" : "", iSeconds);
    }
    else if (iMinutes > 0)
    {
        Format(output, outputsize, "%s%i:%s%.3f", (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10.0) ? "0" : "", iSeconds);
    }
    else
    {
        Format(output, outputsize, "%s%.3f", (iSeconds < 10) ? "0" : "", iSeconds);
    }
}
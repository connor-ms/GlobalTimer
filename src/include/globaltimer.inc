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

#define PREFIX " \x01[\x0BGlobalTimer\x01]"

enum
{
    Track_MainStart,
    Track_MainEnd,
    Track_BonusStart,
    Track_BonusEnd
};

/**
 * Called when a player leaves a zone.
 *
 * @param client      Client index.
 * @param tick        Current server tick.
 * @param zone        Zone left from.
 * @noreturn
 */
forward void OnPlayerLeaveZone(int client, int tick, int zone);

/**
 * Called when a player enters a zone.
 *
 * @param client      Client index.
 * @param tick        Current server tick.
 * @param zone        Zone entered.
 * @noreturn
 */
forward void OnPlayerEnterZone(int client, int tick, int zone);

/**
 * Called when a player changes track. (ex: from main to bonus, or vice-versa)
 *
 * @param client      Client index.
 * @noreturn
 */
forward void OnPlayerTrackChange(int client);

/**
 * Called when a player beats the current server record.
 *
 * @param client      Client index.
 * @param track       Track the run occurred on (main or bonus).
 * @param oldtime     Previous sr.
 * @param newtime     New sr.
 * @noreturn
 */
forward void OnPlayerBeatSr(int client, int track, float oldtime, float newtime);

/**
 * Called when a player beats their pb, but doesn't beat sr.
 *
 * @param client      Client index.
 * @param track       Track the run occurred on (main or bonus).
 * @param oldtime     Client's previous time.
 * @param newtime     New set time.
 * @noreturn
 */
forward void OnPlayerBeatPb(int client, int track, float oldtime, float newtime);

/**
 * Called when a player finishes the map, but doesn't beat pb or sr.
 *
 * @param client      Client index.
 * @param track       Track the run occurred on (main or bonus).
 * @param time        Amount of time it took to complete the track.
 * @param pb          Players current pb.
 * @noreturn
 */
forward void OnPlayerFinishedTrack(int client, int track, float time, float pb);

/**
 * Called when a player's timer starts.
 *
 * @param client      Client index.
 * @param track       Track the timer is running on (main or bonus).
 * @param tick        Tick the timer started.
 * @noreturn
 */
forward void OnPlayerTimerStart(int client, int track, int tick);

/**
 * Gets the zone the client is currently in.
 *
 * @param client      Client index.
 * @return            The index of the zone, or -1 if the client
 *                    isn't in a zone.
 */
native int IsPlayerInZone(int client);

/**
 * Gets the client's current track.
 *
 * @param client      Client index.
 * @return            The current track (main or bonus).
 */
native int GetPlayerTrack(int client);

/**
 * Gets the tick the client's timer started.
 *
 * @param client      Client index.
 * @return            Tick count the timer started at.
 */
 native int GetPlayerStartTick(int client);

/**
 * Gets if the client is in a run.
 *
 * @param client      Client index.
 * @return            Whether or not a player's timer is going.
 */
 native bool IsPlayerInRun(int client);

/**
 * Stops the client's timer.
 *
 * @param client      Client index.
 * @noreturn
 */
native void StopTimer(int client);

/**
 * Gets the smaller of the two numbers.
 *
 * @param num1      A number.
 * @param num2      Another number.
 * @return          The smallest of the two numbers.
 */
stock float min(float num1, float num2)
{
    if (num1 < num2)
        return num1;
    else
        return num2;
}

/**
 * Gets the biggest of two numbers.
 *
 * @param num1      A number.
 * @param num2      Another number.
 * @return          The biggest of the two numbers.
 */
stock float max(float num1, float num2)
{
    if (num1 > num2)
        return num1;
    else
        return num2;
}

/**
 * Gets the average of two numbers.
 *
 * @param num1      A number.
 * @param num2      Another number.
 * @return          The average of the two numbers.
 */
stock float avg(float num1, float num2)
{
    return (num1 + num2) / 2.0;
}

/**
 * Gets the center point between two vectors.
 *
 * @param source    The vector to be modified with results.
 * @param vec1      A vector.
 * @param vec2      Another vector.
 * @noreturn
 */
stock void vecavg(float source[3], float vec1[3], float vec2[3])
{
    source[0] = avg(vec1[0], vec2[0]);
    source[1] = avg(vec1[1], vec2[1]);
    source[2] = avg(vec1[2], vec2[2]);
}

/**
 * Kills a timer and frees its memory.
 *
 * @param timer     A handle to the timer to be cleared.
 * @noreturn
 */
stock ClearTimer(&Handle:timer)
{
    if (timer != INVALID_HANDLE)
    {
        KillTimer(timer);
    }
    timer = INVALID_HANDLE;
}

/**
 * Checks whether a client is valid.
 *
 * @param client    The client to be checked.
 * @return          Whether or not the client is "valid".
 */
stock bool IsValidClient(int client)
{
    return IsClientInGame(client) && IsClientConnected(client) && !IsFakeClient(client);
}

/**
 * Handles errors in a db query.
 *
 * @param db        Database being queried.
 * @param results   Uuhhhh its the results duh
 * @param error     Error message
 * @param any       Whatever tf you want. It doesn't matter what, it won't be used anyway.
 * @noreturn
 */
stock void DB_ErrorHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        PrintToServer("DB error! (%s)", error);
        return;
    }
}

/**
 * Formats a time in seconds to a more readable format (HH:MM:SS.MS)
 *
 * @param time      Time in seconds.
 * @param output    String to be modified with finished format.
 * @param size      Size of string.
 * @param accurate  Whether to round to nearest tenth or thousandth.
 * @noreturn
 */
stock void FormatSeconds(float time, char[] output, int size, bool accurate)
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
        // Fuck you I like ternary operators.
        Format(output, size, accurate ? "%s%i:%s%i:%s%.3f" : "%s%i:%s%i:%s%.1f", (iHours < 10) ? "0" : "", iHours, (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10) ? "0" : "", iSeconds);
    }
    else if (iMinutes > 0)
    {
        Format(output, size, accurate ? "%s%i:%s%.3f" : "%s%i:%s%.1f", (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10.0) ? "0" : "", iSeconds);
    }
    else
    {
        Format(output, size, accurate ? "%s%.3f" : "%s%.1f", (iSeconds < 10) ? "0" : "", iSeconds);
    }
}
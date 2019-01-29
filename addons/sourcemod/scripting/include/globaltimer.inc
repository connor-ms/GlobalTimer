#if defined _globaltimer_included
    #endinput
#endif
#define _globaltimer_included

#define VERSION "0.01a"
#define URL     "www.steamcommunity.com/id/connorms"

enum struct DB
{
    DBType   iType;                 // Type of connection. (MySQL or SQLite)
    bool     bConnected;            // Whether a connection has been made or not.
    Database db;                    // Connection to database.
};

enum
{
    INVALID_TRACK = -1,
    Track_Main    = 0,
    Track_Bonus   = 1
};

enum
{
    INVALID_ZONE = -1,
    Zone_Start   = 0,
    Zone_End     = 1
};

enum DBType
{
    DB_MySQL,    // MySQL specified in databases.cfg
    DB_SQLite,   // SQLite specified in databases.cfg
    DB_Undefined // No entry in databases.cfg (just used for setup, after setup it should be set to SQLite)
};

/**
 * Thanks to PremyslTalich/ColorVariables on GitHub.
 * https://github.com/PremyslTalich/ColorVariables/blob/master/addons/sourcemod/scripting/includes/colorvariables.inc#L966-#L983
*/

char g_sColors[][][] =
{
    { "{white}",      "\x01" },
    { "{darkred}",    "\x02" },
    { "{purple}",     "\x03" },
    { "{green}",      "\x04" },
    { "{olive}",      "\x05" },
    { "{lightgreen}", "\x06" },
    { "{red}",        "\x07" },
    { "{gray}",       "\x08" },
    { "{yellow}",     "\x09" },
    { "{gold}",       "\x10" },
    { "{bluegray}",   "\x0A" },
    { "{blue}",       "\x0B" },
    { "{darkblue}",   "\x0C" },
    { "{gray2}",      "\x0D" },
    { "{orchid}",     "\x0E" },
  
};

char g_sPrefix[128] = " \x01[\x0BGlobalTimer\x01]";

/**
 * Called when a player enters a zone.
 *
 * @param client    Client index.
 * @param tick      Current server tick.
 * @param track     Track type.
 * @param type      Current server tick.
 */
forward void OnPlayerEnterZone(int client, int tick, int track, int type);

/**
 * Called when a player leaves a zone.
 *
 * @param client    Client index.
 * @param tick      Current server tick.
 * @param track     Track type.
 * @param type      Current server tick.
 */
forward void OnPlayerLeaveZone(int client, int tick, int track, int type);

/**
 * Called when a player beats the current server record.
 *
 * @param client    Client index.
 * @param track     Track the run occurred on (main or bonus).
 * @param newtime   New sr.
 * @param oldtime   Previous sr.
 * @noreturn
 */
forward void OnPlayerBeatSr(int client, int track, float newtime, float oldtime);

/**
 * Called when a player beats their pb, but doesn't beat sr.
 *
 * @param client    Client index.
 * @param track     Track the run occurred on (main or bonus).
 * @param newtime   New personal best.
 * @param oldtime   Client's previous time.
 * @noreturn
 */
forward void OnPlayerBeatPb(int client, int track, float newtime, float oldtime);

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
 * Called when a player changes their track.
 *
 * @param client    Client index.
 * @param track     Index of new track. (Main/Bonus)
 */
forward void OnPlayerTrackChange(int client, int track);

/**
 * Returns the player's current track.
 *
 * @param client    Client index.
 */
native int GetPlayerTrack(int client);

/**
 * Stops the player's timer.
 *
 * @param client    Client index.
 * @param notify    Whether the player should be notified.
 */
native void StopTimer(int client, bool notify);

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
 * Formats a time (in seconds) to a more readable format (HH:MM:SS.MS)
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
        Format(output, size, accurate ? "%s%i:%s%i:%s%fs" : "%s%i:%s%i:%s%.1fs", (iHours < 10) ? "0" : "", iHours, (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10) ? "0" : "", iSeconds);
    }
    else if (iMinutes > 0)
    {
        Format(output, size, accurate ? "%s%i:%s%fs" : "%s%i:%s%.1fs", (iMinutes < 10) ? "0" : "", iMinutes, (iSeconds < 10.0) ? "0" : "", iSeconds);
    }
    else
    {
        Format(output, size, accurate ? "%s%fs" : "%s%.1fs", (iSeconds < 10) ? "0" : "", iSeconds);
    }
}

/**
 * Formats readable color codes to "real" colors. Ex: {darkred} -> \x02
 *
 * @param format    String to be formatted.
 * @param size      Size of string.
 * @noreturn
 */
stock void FormatColors(char[] format, int size)
{
    for (int i = 0; i < sizeof(g_sColors); i++)
    {
        ReplaceString(format, size, g_sColors[i][0], g_sColors[i][1], false);
    }
}

/**
 * Reads a KeyValue from a file.
 *
 * @param type      Section name.
 * @param value     Sub section to be read.
 * @param result    String the result will be copied to.
 * @param size      Size of string.
 * @param path      Path (relative to SM installation) to file to be read.
 * @noreturn
 */
stock bool GetKV(const char[] type, const char[] value, char[] result, int size, const char[] path)
{
    char sPath[128];

    BuildPath(Path_SM, sPath, sizeof(sPath), path);

    KeyValues kv = new KeyValues("Values");
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

/**
 * Kills a timer and frees its memory.
 *
 * @param timer     A handle to the timer to be cleared.
 * @noreturn
 */
stock void ClearTimer(Handle &timer)
{
    if (timer != null)
    {
        KillTimer(timer);
    }
    
    timer = null;
}

/**
 * Simple error handler.
 *
 * @param db        Database queried from.
 * @param results   Results from query.
 * @param error     Error message.
 * @param data      Any data being passed.
 * @noreturn
 */
stock void DB_ErrorHandler(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null)
    {
        LogError("Database error (%s)", error);
    }
}
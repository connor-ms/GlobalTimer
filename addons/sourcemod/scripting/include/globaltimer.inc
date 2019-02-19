#if defined _globaltimer_included
    #endinput
#endif
#define _globaltimer_included

#define VERSION "0.01a"
#define URL     "www.steamcommunity.com/id/connorms"

#define MAXSTYLES 8

enum struct DB
{
    DBType   iType;       // Type of connection. (MySQL or SQLite)
    bool     bConnected;  // Whether a connection has been made or not.
    Database db;          // Connection to database.
};

enum struct RunFrame
{
    float fTime;          // Time up until current frame.
    float fOffset;        // Time missed between ticks. (adjusted at start and end only)

    bool  bPaused;        // If timer is currently paused or not.

    int   iTrack;         // Track run is occurring on.
    int   iStyle;         // Style run is occurring on.

    int   iButtons;       // Buttons most recently pressed.
    int   iJumps;         // Amount of jumps until current frame.
    float fSync;          // Average sync up to current point;
    
    float fMaxSpeed;      // Highest speed achieved during run.
};

enum struct RunStats
{
    float fTime;          // Time it took to complete the map.
    float fDifPb;         // Difference between fTime and player's pb.
    float fDifSr;         // Difference between fTime and server record.

    int   iTrack;         // Track run occurred on.
    int   iStyle;         // Style run occurred on.

    int   iJumps;         // Amount of jumps it took to complete the run.
    float fSSJ;           // Player's speed on 6th jump during run.
    float fSync;          // Average sync throughout run.

    float fAvgSpeed;      // Average speed throughout run.
    float fMaxSpeed;      // Highest speed achieved during run.
};

enum struct RunDBInfo
{
    int   iId;

    float fTime;
    int   iDate;

    int   iStyle;
    int   iTrack;

    int   iJumps;
    float fSync;
    float fSSJ;

    float fAvgSpeed;      // Average speed throughout run.
    float fMaxSpeed;      // Highest speed achieved during run.
};

enum struct Style
{
    int iIndex;

    char sName[64];
    char sShortcut[16];

    int iAllowForwards;
    int iAllowLeft;
    int iAllowRight;
    int iAllowBack;

    bool bAutohop;
    bool bAllowPrespeed;
    int  iCustom;
};

enum struct Zone
{
    int  iEntityIndex; // Entity index for zone.
    int  iTrack;       // Main/Bonus.
    int  iType;        // Start/End/Stage.
    int  iStage;       // 0 if start/end, otherwise stage #.
    bool bValid;       // Whether or not zone entity has been created.
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
    Zone_End     = 1,
    Zone_Stage   = 2
};

enum
{
    Accuracy_Low  = 0, // Rounds time to 1 decimal place
    Accuracy_Med  = 1, // Rounds time to 3 decimal places
    Accuracy_High = 2  // Doesn't round time (6 decimal places)
};

enum DBType
{
    DB_MySQL,    // MySQL specified in databases.cfg
    DB_SQLite,   // SQLite specified in databases.cfg
    DB_Undefined // No entry in databases.cfg (just used for setup, after setup it should be set to SQLite)
};

enum
{
    KeyReq_Disabled, // Disallow keypress
    KeyReq_Enabled,  // Allow keypress
    KeyReq_Required  // Require keypress 
};

enum
{
    CustomStyle_HSW    = 1,
    CustomStyle_ADOnly = 2
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
    { "{orchid}",     "\x0E" }
};

char g_sPrefix[128] = " \x01[\x0BGlobalTimer\x01]";

char g_sTracks[2][5] =
{
    "Main",
    "Bonus"
};

char g_sZoneTypes[][] =
{
    "Start",
    "End"
};

ArrayList g_aZoneNames;

/**
 * Called when a player enters a zone.
 *
 * @param client    Client index.
 * @param tick      Current server tick.
 * @param track     Track type.
 * @param type      Current server tick.
 * @noreturn
 */
forward void OnPlayerEnterZone(int client, int tick, int track, int type);

/**
 * Called when a player leaves a zone.
 *
 * @param client    Client index.
 * @param tick      Current server tick.
 * @param track     Track type.
 * @param type      Current server tick.
 * @noreturn
 */
forward void OnPlayerLeaveZone(int client, int tick, int track, int type);

/**
 * Called when a player's timer is incremented.
 *
 * @param client    Client index.
 * @param info      Information for current frame.
 * @param amount    Amount timer will be incremented by.
 * @noreturn
 */
forward void OnPlayerTimerIncrement(int client, RunFrame info, float amount);

/**
 * Called when a player beats the current server record.
 *
 * @param client    Client index.
 * @param style     Style the run occurred on.
 * @param track     Track the run occurred on (main or bonus).
 * @param newtime   New sr.
 * @param oldtime   Previous sr.
 * @noreturn
 */
forward void OnPlayerBeatSr(int client, int style, int track, float newtime, float oldtime);

/**
 * Called when a player beats their pb, but doesn't beat sr.
 *
 * @param client    Client index.
 * @param stats     Information about the run.
 * @param oldpb     Player's previous pb.
 * @noreturn
 */
forward void OnPlayerBeatPb(int client, RunStats stats, float oldpb);

/**
 * Called when a player finishes the map, but doesn't beat pb or sr.
 *
 * @param client      Client index.
 * @param stats       Information about the run.
 * @param pb          Players current pb.
 * @noreturn
 */
forward void OnPlayerFinishedTrack(int client, RunStats stats, float pb);

/**
 * Called when the server record for each track is loaded.
 *
 * @param time        Time (in seconds) for record.
 * @param info        More detailed information about run. (see RunDBInfo)
 * @noreturn
 */
forward void OnSrLoaded(float time, RunDBInfo info);

/**
 * Called when the database responded with player's pb for each track.
 *
 * @param client      Client index.
 * @param style       Style index.
 * @param track       Track the run occurred on (main or bonus).
 * @param time        Player's pb (in seconds) for track.
 * @noreturn
 */
forward void OnPbLoaded(int client, int style, int track, float time);

/**
 * Called when a player changes their track.
 *
 * @param client    Client index.
 * @param track     Index of new track. (Main/Bonus)
 * @noreturn
 */
forward void OnPlayerTrackChange(int client, int track);

/**
 * Called when a player changes their style.
 *
 * @param client    Client index.
 * @param settings  Settings for new style.
 * @noreturn
 */
forward void OnPlayerStyleChange(int client, Style settings);

/**
 * Stops the player's timer.
 *
 * @param client    Client index.
 * @param notify    Whether the player should be notified.
 * @noreturn
 */
native void StopTimer(int client, bool notify);

/**
 * Gets if the player is in a run or not.
 *
 * @param client    Client index.
 * @return          Whether the player is in a run or not.
 */
native bool IsPlayerInRun(int client);

/**
 * Gets the player's most recent run frame.
 *
 * @param client    Client index.
 * @param output    Array to copy results to.
 * @noreturn 
 */
native void GetPlayerFrame(int client, any output[sizeof(RunFrame)]);

/**
 * Gets the player's pb for the specified track.
 *
 * @param client    Client index.
 * @param style     Style to get pb from.
 * @param track     Track to get pb from.
 * @return          Player's pb for track (in seconds).
 */
native float GetPlayerPb(int client, int style, int track);

/**
 * Gets the player's speed during last jump.
 *
 * @param client    Client index.
 * @return          Player's speed.
 */
native float GetPlayerJumpSpeed(int client);

/**
 * Gets whether or not the player is inside a zone.
 * -1 = not in a zone
 * 0 or higher = zone index (see zone enum for indexes)
 *
 * @param client    Client index.
 * @return          Player's current zone.
 */
native int GetPlayerCurrentZone(int client);

/**
 * Finds the index of a zone by track and zone type.
 *
 * @param track     Track type. (main/bonus)
 * @param type      Zone type.
 * @return          Zone's index. (-1 if none found)
 */
native int FindZone(int track, int type);

/**
 * Copies zone info off of zone index.
 *
 * @param index     Index returned by FindZone.
 * @param output    Array to copy zone info into.
 * @noreturn
 */
native void GetZoneInfo(int index, any output[sizeof(Zone)]);

/**
 * Gets the server record for the specified track.
 *
 * @param style     Style index.
 * @param track     Track type.
 * @return          Server record for specified style/track.
 */
native float GetSr(int style, int track);

/**
 * Gets the settings for player's current style.
 *
 * @param client    Client index.
 * @param output    Array to copy results into.
 * @noreturn
 */
native void GetPlayerStyleSettings(int client, any output[sizeof(Style)]);

/**
 * Gets the rank out of all runs for specified time on style + track combo.
 *
 * @param time      Time to find rank of.
 * @param style     Style times to compare time to.
 * @param track     Track times to compare time to.
 * @return          Index of time compared to other times for style + track combo.
 */
native int GetPlacementByTime(float time, int style, int track);

/**
 * Gets the total amount of runs for specified style + track combo.
 *
 * @param style     Style to check times from.
 * @param track     Track to check times from.
 * @return          Total amount of runs completed.
 */
native int GetTotalTimes(int style, int track);

/**
 * Restarts a players timer and teleports them to the start zone.
 *
 * @param client    Client index.
 * @noreturn
 */
native void ForceRestartPlayer(int client);

/**
 * Checks if the entity is a valid player.
 *
 * @param entity    Entity index.
 * @return          Whether or not the entity is a player.
 */
stock bool IsPlayer(int entity)
{
    return (entity <= MAXPLAYERS && entity != 0 && IsClientConnected(entity));
}

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
 * @param accurate  Amount the time should be rounded to.
 *                    - Low: 1 decimal place
 *                    - Medium: 3 decimal places
 *                    - High: No rounding (6 decimal places)
 * @param shortened Whether minutes should be cut out if the time is < 1 minute.
 * @noreturn
 */
stock void FormatSeconds(float seconds, char[] output, int size, int accuracy, bool sign, bool shortened)
{
    int   iHours   = RoundToFloor(FloatAbs(seconds) / 3600);
    int   iMinutes = RoundToFloor(FloatAbs(seconds) / 60 - (iHours * 60));
    float fSeconds = FloatAbs(seconds) - (iHours * 3600) - (iMinutes * 60);

    char sSeconds[12];
    char cSign;

    if (accuracy == Accuracy_Low)
    {
        Format(sSeconds, sizeof(sSeconds), "%.1fs", fSeconds);
    }
    else if (accuracy == Accuracy_Med)
    {
        Format(sSeconds, sizeof(sSeconds), "%.3fs", fSeconds);
    }
    else if (accuracy == Accuracy_High)
    {
        Format(sSeconds, sizeof(sSeconds), "%fs", fSeconds);
    }

    if (sign)
    {
        cSign = (seconds < 0.0) ? '-' : '+';
    }
    else
    {
        cSign = '\0';
    }

    if (iHours > 0)
    {
        Format(output, size, "%s%s%i:%s%i:%s", cSign, (iHours < 10) ? "0" : "", iHours, (iMinutes < 10) ? "0" : "", iMinutes, sSeconds);
    }
    else
    {
        if (shortened && iMinutes == 0)
        {
            Format(output, size, "%s%s", cSign, sSeconds);
        }
        else
        {
            Format(output, size, "%s%s%i:%s%s", cSign, (iMinutes < 10) ? "0" : "", iMinutes, (fSeconds < 10.0) ? "0" : "", sSeconds);
        }
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
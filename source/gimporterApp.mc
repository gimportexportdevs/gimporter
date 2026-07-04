import Toybox.Lang;

using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;
using Toybox.Timer as TIME;
using Toybox.System as System;
using Toybox.Graphics as GFX;

function getApp() as gimporterApp {
    return App.getApp() as gimporterApp;
}

const DEFAULT_PORT = 22222;

// Menu item identifiers indexed by position; shared by TrackChooser and
// SimilarCourseChooser (the old WatchUi.Menu identifies items by Symbol
// and caps at 16 items).
const ITEM_SYMBOLS = [:ITEM_0, :ITEM_1, :ITEM_2, :ITEM_3,
                      :ITEM_4, :ITEM_5, :ITEM_6, :ITEM_7,
                      :ITEM_8, :ITEM_9, :ITEM_10, :ITEM_11,
                      :ITEM_12, :ITEM_13, :ITEM_14, :ITEM_15] as Array<Symbol>;

function itemToSym(i as Number) as Symbol {
    return ITEM_SYMBOLS[i];
}

function symToItem(sym as Symbol) as Number {
    for (var i = 0; i < ITEM_SYMBOLS.size(); i++) {
        if (sym.equals(ITEM_SYMBOLS[i])) {
            return i;
        }
    }
    return 0;
}

// Map Communications error codes the user can act on to specific
// messages; anything else falls through to the caller's default.
function commErrorString(responseCode as Number, def as ResourceId) as ResourceId {
    if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
        return Rez.Strings.BluetoothDisconnected;
    }
    if (responseCode == Comm.STORAGE_FULL) {
        return Rez.Strings.StorageFull;
    }
    if (responseCode == Comm.NETWORK_REQUEST_TIMED_OUT) {
        return Rez.Strings.DownloadTimeout;
    }
    if (responseCode == Comm.NETWORK_RESPONSE_TOO_LARGE) {
        return Rez.Strings.ResponseTooLarge;
    }
    return def;
}

class PortRequestListener extends Comm.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        System.println("Port request sent to Android app");
    }

    function onError() {
        System.println("Failed to send port request");
        // Fall back to default port with delay to let BLE recover
        getApp().fallbackToDefaultPort();
    }
}

class gimporterApp extends App.AppBase {
    var tracks as Array? = null;
    var trackToStart as String?;
    var canLoadList as Boolean;
    var status as String or ResourceId = "";
    var mGPXorFIT as String;
    var bluetoothTimer as TIME.Timer;
    var exitTimer as TIME.Timer;
    var mIntent as System.Intent? = null;
    var mServerPort as Number = DEFAULT_PORT;  // Updated dynamically via the port handshake
    var mPendingTrackIndex as Number? = null;  // Track index to load after port is received
    var mPortResponseTimer as TIME.Timer?;  // Timer for port response timeout
    var mSimilarCourses as Array? = null;  // Store similar courses for user selection
    var mPortFallbackTimer as TIME.Timer?;  // Timer for delayed fallback after BLE disruption
    var mPortRequestPending as Boolean = false;  // One-shot gate: port resolution may dispatch only once per request
    var mDownloadPending as Boolean = false;  // Download in flight; cleared when the user backs out

    function initialize() {
        AppBase.initialize();

        mGPXorFIT = Ui.loadResource(Rez.Strings.GPXorFIT);
        System.println("GPXorFit = " + mGPXorFIT);

        canLoadList = true;
        bluetoothTimer = new TIME.Timer();
        exitTimer = new TIME.Timer();
    }

    // onStart() is called on application start up
    function onStart(state as Lang.Dictionary?) as Void {
        status = Rez.Strings.PressStart;
    }

    // onStop() is called when your application is exiting
    function onStop(state as Lang.Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [ Ui.Views ] or [ Ui.Views, Ui.InputDelegates ] {
        return [ new gimporterView(), new gimporterDelegate() ];
    }

    function getStatus() as String {
        return status;
    }

    function getTracks() as Array {
        return tracks;
    }

    function stopPortTimers() as Void {
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }
        if (mPortFallbackTimer != null) {
            mPortFallbackTimer.stop();
        }
    }

    // Helper to proceed after port is resolved (either received or fallback).
    // Dispatches to the correct load function based on pending state.
    // One-shot per port request: the timeout fallback timer, a late reply and
    // a transmit error can all arrive for the same request, so every caller
    // funnels through the mPortRequestPending gate.
    function proceedAfterPortResolved() as Void {
        if (!mPortRequestPending) {
            return;
        }
        mPortRequestPending = false;
        stopPortTimers();
        if (Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(null);
        }
        if (mPendingTrackIndex != null) {
            var index = mPendingTrackIndex;
            mPendingTrackIndex = null;
            loadTrackNumWithPort(index);
        } else {
            loadTrackListWithPort();
        }
    }

    // Delayed fallback callback used after BLE disruption from Comm.transmit().
    // Gives the BLE channel time to recover before making the HTTP request.
    function onPortFallbackDelayed() as Void {
        proceedAfterPortResolved();
    }

    // Fall back to default port with a short delay.
    // The delay allows the BLE channel to recover after a failed Comm.transmit(),
    // which can disrupt the BLE proxy on older devices/firmware.
    function fallbackToDefaultPort() as Void {
        if (!mPortRequestPending) {
            return;
        }
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }
        mServerPort = DEFAULT_PORT;
        if (mPortFallbackTimer == null) {
            mPortFallbackTimer = new TIME.Timer();
        }
        mPortFallbackTimer.start(method(:onPortFallbackDelayed), 500, false);
    }

    function requestPortFromAndroid() as Void {
        mPortRequestPending = true;

        // Check if phone is connected first
        var settings = System.getDeviceSettings();
        if (!settings.phoneConnected) {
            System.println("Phone not connected, using default port");
            mServerPort = DEFAULT_PORT;
            proceedAfterPortResolved();
            return;
        }

        try {
            status = "Requesting port...";
            Ui.requestUpdate();

            // Check if phone app messaging is available
            if (Comm has :registerForPhoneAppMessages) {
                // Register to receive the response before sending
                Comm.registerForPhoneAppMessages(method(:onPortReceived));

                // Start timeout timer - 1 second to wait for response
                if (mPortResponseTimer == null) {
                    mPortResponseTimer = new TIME.Timer();
                }
                mPortResponseTimer.start(method(:onPortResponseTimeout), 1000, false);

                // Send request to Android app
                var message = ["GET_PORT"];
                Comm.transmit(message, null, new PortRequestListener());
            } else {
                // Device doesn't support phone app messaging, use default port
                System.println("Device doesn't support phone app messaging, using default port");
                mServerPort = DEFAULT_PORT;
                proceedAfterPortResolved();
            }
        } catch (ex) {
            System.println("Error requesting port: " + ex.getErrorMessage());
            // Stop timeout timer
            if (mPortResponseTimer != null) {
                mPortResponseTimer.stop();
            }
            // Fall back to default port with delay to let BLE recover
            fallbackToDefaultPort();
        }
    }

    function onPortReceived(msg as Comm.PhoneAppMessage) as Void {
        if (!mPortRequestPending) {
            // Stray message (duplicate reply, queued leftover from an
            // earlier request) - the listener also fires for those.
            System.println("Ignoring phone message: no port request pending");
            return;
        }

        // Stop the timeout timer since we got a response
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }

        var port = msg.data;
        if (port instanceof Number && port > 0 && port <= 65535) {
            // Received port number
            mServerPort = port;
            System.println("Received port from Android app: " + mServerPort);
            proceedAfterPortResolved();
        } else {
            // Unexpected response type, fall back to default port
            System.println("Unexpected port response type, using default port");
            mServerPort = DEFAULT_PORT;
            proceedAfterPortResolved();
        }
    }

    function onPortResponseTimeout() as Void {
        System.println("Port response timeout, using default port");
        // Timeout reached, fall back to default port with delay to let BLE recover
        fallbackToDefaultPort();
    }

    function loadTrackList() as Void {
        tracks = null;
        trackToStart = null;
        mIntent = null;
        mSimilarCourses = null;
        mPendingTrackIndex = null;

        var settings = System.getDeviceSettings();

        if (! settings.phoneConnected) {
            bluetoothTimer.stop();
            status = Rez.Strings.WaitingForBluetooth;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        if ((settings has :connectionInfo) && settings.connectionInfo.hasKey(:wifi) && (settings.connectionInfo[:wifi].state == System.CONNECTION_STATE_CONNECTED)) {
            bluetoothTimer.stop();
            status = Rez.Strings.SwitchOffWifi;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        // Block re-entry now - the port handshake below is asynchronous
        canLoadList = false;

        // Request port from Android app before making HTTP request
        requestPortFromAndroid();
    }

    function loadTrackListWithPort() as Void {
        status = Rez.Strings.GettingTracklist;
        canLoadList = false;
        try {
            var url = "http://127.0.0.1:" + mServerPort + "/dir.json";
            System.println("Requesting track list from: " + url);
            Comm.makeWebRequest(
                url,
                {
                    "type" => mGPXorFIT,
                    "short" => "1",
                    "longname" => "1" },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onReceiveTracks) );
        } catch( ex ) {
            canLoadList = true;
            status = ex.getErrorMessage();
        }

        Ui.requestUpdate();
    }

    function onReceiveTracks(responseCode as Number, data as Dictionary) as Void {
        status = "";
        canLoadList = true;

        if (responseCode != 200) {
            System.println("Code " + responseCode.toString());
            status = commErrorString(responseCode, Rez.Strings.ConnectionFailed);
            Ui.requestUpdate();
            return;
        }

        if (!(data instanceof Toybox.Lang.Dictionary) || !data.hasKey("tracks")) {
            System.println("data is no Dictionary or has no track key");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        tracks = data["tracks"];

        if (!(tracks instanceof Toybox.Lang.Array)) {
            System.println("tracks != Array");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        if (tracks.size() == 0) {
            System.println("tracks is empty");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        // Every element must be a Dictionary with String "url" and "title";
        // TrackChooser and loadTrackNumWithPort rely on this shape unchecked.
        for (var i = 0; i < tracks.size(); i++) {
            var track = tracks[i];
            if (!(track instanceof Toybox.Lang.Dictionary)
                || !(track["url"] instanceof Toybox.Lang.String)
                || !(track["title"] instanceof Toybox.Lang.String)) {
                System.println("track " + i + " is malformed");
                status = Rez.Strings.ConnectionFailed;
                tracks = null;
                Ui.requestUpdate();
                return;
            }
        }

        Ui.pushView(new TrackChooser(0), new TrackChooserDelegate(0), Ui.SLIDE_IMMEDIATE);

    }

    function loadTrackNum(index as Number) as Void {
        System.println("loadTrack: " + tracks[index].toString());

        mSimilarCourses = null;
        canLoadList = false;

        // Store the index for later use
        mPendingTrackIndex = index;

        // Request port from Android app before downloading
        requestPortFromAndroid();
    }

    function loadTrackNumWithPort(index as Number) as Void {
        if (tracks == null || index >= tracks.size()) {
            // The list was reloaded or cleared while the port handshake
            // was in flight; the stored index no longer means anything.
            System.println("track list changed, aborting load");
            canLoadList = true;
            status = Rez.Strings.NoTracks;
            Ui.requestUpdate();
            return;
        }

        var trackurl = (tracks[index] as Dictionary)["url"];
        trackToStart = (tracks[index] as Dictionary)["title"];

        if ((trackurl.length() < 7) || (!trackurl.substring(0, 7).equals("http://"))) {
            trackurl = "http://127.0.0.1:" + mServerPort + "/" + trackurl;
        }

        status = Rez.Strings.Downloading;
        canLoadList = false;
        System.println("GPXorFIT: " + mGPXorFIT);

        Ui.pushView(
            new gimporterView(),
            new gimporterDelegate(),
            Ui.SLIDE_IMMEDIATE );
        Ui.requestUpdate();

        mDownloadPending = true;
        try {
            if (mGPXorFIT.equals("FIT")) {
                System.println("Downloading FIT");
                Comm.makeWebRequest(
                    trackurl,
                    {
                        "type" => "FIT",
                        "longname" => "1" },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_GET,
                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT },
                    method(:onReceiveTrack) );
            } else {
                System.println("Downloading GPX");
                Comm.makeWebRequest(
                    trackurl,
                    {
                        "type" => "GPX",
                        "longname" => "1" },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_GET,
                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_GPX },
                    method(:onReceiveTrack) );
            }
        } catch( ex ) {
            mDownloadPending = false;
            canLoadList = true;
            status = Rez.Strings.DownloadNotSupported;
        }

        Ui.requestUpdate();
    }

    function doExitInto() as Void {
        if (mIntent != null) {
            System.exitTo(mIntent);
            mIntent = null;
        }
    }

    function exitInto(intent as System.Intent) as Void {
        if (intent != null) {
            mIntent = intent;
            exitTimer.start(method(:doExitInto), 200, false);
        }
    }

    function getSimilarCourses() as Array {
        return mSimilarCourses;
    }

    function launchSimilarCourse(index as Number) as Void {
        if (mSimilarCourses != null && index < mSimilarCourses.size()) {
            var course = mSimilarCourses[index];
            System.println("Launching similar course: " + course.getName());
            exitInto(course.toIntent());
            mSimilarCourses = null;
        }
    }

    function onReceiveTrack(responseCode as Number, downloads as PC.Iterator?) as Void {
        System.println("onReceiveTrack");

        if (!mDownloadPending) {
            // The user backed out while the download was in flight; the
            // view this callback wants to manipulate is no longer on top.
            System.println("download cancelled, ignoring result");
            return;
        }
        mDownloadPending = false;

        if (responseCode != 200) {
            System.println("Code: " + responseCode);
            canLoadList = true;
            status = commErrorString(responseCode, Rez.Strings.DownloadFailed);
            Ui.requestUpdate();
            return;
        }
        else if (downloads == null) {
            System.println("downloads == null");
            canLoadList = true;
            status = Rez.Strings.DownloadFailed;
            Ui.requestUpdate();
            return;
        }
        else {
            var download = downloads.next();
            System.println("onReceiveTrack: " + (download == null ? null : download.getName() + "/" + download.getId()));

            // FIXME: Garmin
            // Without switchToView() the widget is gone
            Ui.switchToView(new gimporterView(), new gimporterDelegate(), Ui.SLIDE_IMMEDIATE);

            status = Rez.Strings.DownloadComplete;

            if (download != null) {
                Ui.requestUpdate();
                exitInto(download.toIntent());
                return;
            }

            status = Rez.Strings.AlreadyDownloaded;

            if (trackToStart == null) {
                System.println("no track name to search for");
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                canLoadList = true;
                status = Rez.Strings.ImportFailed;
                Ui.requestUpdate();
                return;
            }

            var ret = false;
            mSimilarCourses = null;

            if (PC has :getAppCourses) {
                System.println("Searching in App courses");
                ret = searchCourse(PC.getAppCourses());
            }
            if ((ret == false) && (PC has :getCourses)) {
                System.println("Searching in courses");
                ret = searchCourse(PC.getCourses());
            }

            if ((ret == false) && (PC has :getAppTracks)) {
                System.println("Searching in App tracks");
                ret = searchCourse(PC.getAppTracks());
            }
            if ((ret == false) && (PC has :getTracks)) {
                System.println("Searching in tracks");
                ret = searchCourse(PC.getTracks());
            }

            if ((ret == false ) && (PC has :getAppRoutes)) {
                System.println("Searching in App routes");
                ret = searchCourse(PC.getAppRoutes());
            }
            if ((ret == false ) && (PC has :getRoutes)) {
                System.println("Searching in routes");
                ret = searchCourse(PC.getRoutes());
            }

            // Check if we found similar courses to present to user
            if (mSimilarCourses != null && mSimilarCourses.size() > 0) {
                System.println("Presenting " + mSimilarCourses.size() + " similar courses to user");
                Ui.pushView(new SimilarCourseChooser(), new SimilarCourseChooserDelegate(), Ui.SLIDE_IMMEDIATE);
            } else {
                // No similar courses found - import failed
                System.println("No similar courses found, import failed");
                Ui.popView(Ui.SLIDE_IMMEDIATE);
                canLoadList = true;
                status = Rez.Strings.ImportFailed;
            }

            Ui.requestUpdate();
            return;
        }
    }

    function normalizeName(name as String) as String {
        var normalized = name;
        var len = normalized.length();
        
        // Remove common course suffixes
        if ((len > 11) && normalized.substring(len-11, len).equals("_course.fit")) {
            normalized = normalized.substring(0, len-11);
        } else if ((len > 4) && (normalized.substring(len-4, len).equals(".fit") || normalized.substring(len-4, len).equals(".gpx"))) {
            normalized = normalized.substring(0, len-4);
        }
        
        return normalized;
    }

    function searchCourse(cit as PC.Iterator) as Boolean {
        var course;
        var startcourse = null;
        var partialMatches = [] as Array;
        var sclen = 0;
        var normalizedTrackName = normalizeName(trackToStart);
        var tlen = normalizedTrackName.length();

        System.println("Searching for track: '" + trackToStart + "' (normalized: '" + normalizedTrackName + "')");

        // Search for the longest coursename matching ours
        while (cit != null) {
            course = cit.next();
            if (course == null) {
                break;
            }
            var coursename = course.getName();
            var normalizedCourseName = normalizeName(coursename);
            var clen = normalizedCourseName.length();

            System.println("Comparing with course: '" + coursename + "' (normalized: '" + normalizedCourseName + "')");

            // Check for exact or prefix matches first
            var isExactMatch = false;
            var isPartialMatch = false;
            
            if (normalizedCourseName.equals(normalizedTrackName)) {
                isExactMatch = true;
                System.println("  Exact match found!");
            } else if (clen <= tlen && normalizedTrackName.substring(0, clen).equals(normalizedCourseName)) {
                isExactMatch = true;
                System.println("  Prefix match found!");
            } else if (clen > tlen && normalizedCourseName.substring(0, tlen).equals(normalizedTrackName)) {
                // Track name is a prefix of course name
                isPartialMatch = true;
                System.println("  Partial match found (track is prefix of course)!");
            }

            if (isExactMatch) {
                // Skip if we already found a longer exact match
                if (sclen > clen) {
                    System.println("  Skipped: already found longer exact match");
                    continue;
                }
                startcourse = course;
                sclen = clen;
                System.println("  Selected as best exact match so far");
            } else if (isPartialMatch) {
                // Collect all partial matches
                partialMatches.add(course as Object);
                System.println("  Added to partial matches list");
            } else {
                System.println("  No match");
            }
        }

        if (startcourse != null) {
            System.println("Found exact course: " + startcourse.getName() + " asking for start");
            mSimilarCourses = null;
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            canLoadList = true;
            status = Rez.Strings.PressStart;
            // FIXME: Garmin
            // I can't do System.exitTo(course.toIntent())
            // It causes the Fenix5 to be in a strange state
            exitInto(startcourse.toIntent()); // workaround
            return true;
        } else if (partialMatches.size() > 0) {
            System.println("Found " + partialMatches.size() + " similar courses");
            mSimilarCourses = partialMatches;
            return true;
        } else {
            System.println("No matching course found for: " + trackToStart);
        }
        return false;
    }
}



class gimporterView extends Ui.View {
    var st as Ui.Text?;
    var ps as String or ResourceId = "";
    var app as gimporterApp;

    function initialize() {
        View.initialize();
        app = $.getApp();
    }

    function onLayout(dc as GFX.Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
        st = findDrawableById("status");
        ps = Ui.loadResource(Rez.Strings.PressStart);
    }

    function onUpdate(dc as GFX.Dc) as Void {
        var status = app.getStatus();
        if (status.equals("")) {
            st.setText(ps);
        } else {
            st.setText(status);
        }

        View.onUpdate(dc);
    }
}

class gimporterDelegate extends Ui.BehaviorDelegate {
    var app as gimporterApp;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onBack() as Boolean {
        // Cancel whatever is in flight - callbacks check these flags and
        // bail out instead of manipulating a view stack we just changed.
        app.canLoadList = true;
        app.status = Rez.Strings.PressStart;
        app.mSimilarCourses = null;
        app.mPendingTrackIndex = null;
        app.mDownloadPending = false;
        app.mPortRequestPending = false;
        app.stopPortTimers();
        Ui.requestUpdate();
        return false;
    }

    function onMenu() as Boolean {
        if (app.canLoadList) {
            app.loadTrackList();
        }
        return true;
    }

    function onSelect() as Boolean {
        if (app.canLoadList) {
            app.loadTrackList();
        }
        return true;
    }
}

class SimilarCourseChooser extends Ui.Menu {

    function initialize() {
        var app = $.getApp();
        Menu.initialize();
        Menu.setTitle(Rez.Strings.SimilarCourseChooserTitle);
        var courses = app.getSimilarCourses();
        
        if (courses != null) {
            for(var i = 0; i < courses.size() && i < ITEM_SYMBOLS.size(); i++) {
                var course = courses[i];
                Menu.addItem(
                    course.getName(),
                    $.itemToSym(i) );
            }
        }
    }
}

class SimilarCourseChooserDelegate extends Ui.MenuInputDelegate {
    var app as gimporterApp;

    function initialize() {
        MenuInputDelegate.initialize();
        app = $.getApp();
    }

    function onMenuItem(item as Symbol) as Void {
        app.launchSimilarCourse($.symToItem(item));
    }
}

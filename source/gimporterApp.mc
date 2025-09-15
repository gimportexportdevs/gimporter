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

class PortRequestListener extends Comm.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() {
        System.println("Port request sent to Android app");
    }

    function onError() {
        System.println("Failed to send port request");
        // Fall back to default port
        var app = getApp();
        app.mServerPort = 22222;
        if (app.mPendingTrackIndex != null) {
            var index = app.mPendingTrackIndex;
            app.mPendingTrackIndex = null;
            app.loadTrackNumWithPort(index);
        } else {
            app.loadTrackListWithPort();
        }
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
    var mServerPort as Number = 22222;  // Default port, will be updated dynamically
    var mPendingTrackIndex as Number? = null;  // Track index to load after port is received
    var mPortResponseTimer as TIME.Timer?;  // Timer for port response timeout
    var mSimilarCourses as Array? = null;  // Store similar courses for user selection

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
        //loadTrackList();
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

    function requestPortFromAndroid() as Void {
        // Check if phone is connected first
        var settings = System.getDeviceSettings();
        if (!settings.phoneConnected) {
            System.println("Phone not connected, using default port");
            mServerPort = 22222;
            if (mPendingTrackIndex != null) {
                var index = mPendingTrackIndex;
                mPendingTrackIndex = null;
                loadTrackNumWithPort(index);
            } else {
                loadTrackListWithPort();
            }
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
                mServerPort = 22222;
                if (mPendingTrackIndex != null) {
                    var index = mPendingTrackIndex;
                    mPendingTrackIndex = null;
                    loadTrackNumWithPort(index);
                } else {
                    loadTrackListWithPort();
                }
            }
        } catch (ex) {
            System.println("Error requesting port: " + ex.getErrorMessage());
            // Stop timeout timer
            if (mPortResponseTimer != null) {
                mPortResponseTimer.stop();
            }
            // Fall back to default port
            mServerPort = 22222;
            if (mPendingTrackIndex != null) {
                var index = mPendingTrackIndex;
                mPendingTrackIndex = null;
                loadTrackNumWithPort(index);
            } else {
                loadTrackListWithPort();
            }
        }
    }

    function onPortReceived(msg as Comm.PhoneAppMessage) as Void {
        // Stop the timeout timer since we got a response
        if (mPortResponseTimer != null) {
            mPortResponseTimer.stop();
        }
        
        if (msg.data instanceof Number) {
            // Received port number
            mServerPort = msg.data as Number;
            System.println("Received port from Android app: " + mServerPort);

            // Check if we were loading a specific track or the track list
            if (mPendingTrackIndex != null) {
                var index = mPendingTrackIndex;
                mPendingTrackIndex = null;
                loadTrackNumWithPort(index);
            } else {
                // Loading track list
                loadTrackListWithPort();
            }
        }
    }
    
    function onPortResponseTimeout() as Void {
        System.println("Port response timeout, using default port");
        // Timeout reached, use default port
        mServerPort = 22222;
        
        if (mPendingTrackIndex != null) {
            var index = mPendingTrackIndex;
            mPendingTrackIndex = null;
            loadTrackNumWithPort(index);
        } else {
            loadTrackListWithPort();
        }
    }

    function loadTrackList() as Void {
        tracks = null;
        trackToStart = null;
        mIntent = null;

        var settings = System.getDeviceSettings();

        if (! settings.phoneConnected) {
            bluetoothTimer.stop();
            status = Rez.Strings.WaitingForBluetooth;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

        if ((settings has :connectionInfo) && (settings.connectionInfo has :wifi) && (settings.connectionInfo[:wifi].state == System.CONNECTION_STATE_CONNECTED)) {
            bluetoothTimer.stop();
            status = Rez.Strings.SwitchOffWifi;
            bluetoothTimer.start(method(:loadTrackList), 1000, false);
            Ui.requestUpdate();
            return;
        }

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
                    :headers => {
                        "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON },
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

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }

        if (responseCode != 200) {
            System.println("data == null\nCode " + responseCode.toString() + "\n");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        if (! data.hasKey("tracks")) {
            System.println("data has no track key");
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        tracks = data["tracks"];

        if (tracks == null) {
            System.println("tracks == null");
            status = Rez.Strings.NoTracks;
            Ui.requestUpdate();
            return;
        }

        if (!(tracks instanceof Toybox.Lang.Array)) {
            System.println("tracks != Array");
            status = Rez.Strings.NoTracks;
            tracks = null;
            Ui.requestUpdate();
            return;
        }

        Ui.pushView(new TrackChooser(0), new TrackChooserDelegate(0), Ui.SLIDE_IMMEDIATE);

    }

    function loadTrackNum(index as Number) as Void {
        System.println("loadTrack: " + tracks[index].toString());

        // Store the index for later use
        mPendingTrackIndex = index;

        // Request port from Android app before downloading
        requestPortFromAndroid();
    }

    function loadTrackNumWithPort(index as Number) as Void {
        // TODO: check hasKey
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

    function onReceiveTrack(responseCode as Number, downloads as PC.Iterator) as Void {
        System.println("onReceiveTrack");

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }
        else if (responseCode != 200) {
            System.println("Code: " + responseCode);
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

            // if (trackToStart.length() > 4) {
            //     var postfix = trackToStart.substring(trackToStart.length()-4, trackToStart.length()).toLower();
            //     if (postfix.equals(".fit") || postfix.equals(".gpx")) {
            //         trackToStart = trackToStart.substring(0, trackToStart.length()-4);
            //     }
            // }
            // if (trackToStart.length() > 15) {
            //     trackToStart = trackToStart.substring(0, 15);
            // }

            var ret = false;

            if (PC has :getAppCourses) {
                System.println("Searching in App courses");
                ret = searchCourse(PC.getAppCourses());
            }
            if (PC has :getCourses) {
                System.println("Searching in courses");
                ret = searchCourse(PC.getCourses());
            }

            if ((ret == false) && (PC has :getAppTracks)) {
                System.println("Searching in App tracks");
                ret = searchCourse(PC.getTracks());
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
        app.canLoadList = true;
        app.status = Rez.Strings.PressStart;
        // Clear any pending similar courses
        app.mSimilarCourses = null;
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
            for(var i = 0; i < courses.size() && i < 16; i++) {
                var course = courses[i];
                Menu.addItem(
                    course.getName(),
                    toSym(i) );
            }
        }
    }

    function toSym(i as Number) as Symbol {
        if (i == 0) {
            return :ITEM_0;
        } else if (i == 1) {
            return :ITEM_1;
        } else if (i == 2) {
            return :ITEM_2;
        } else if (i == 3) {
            return :ITEM_3;
        } else if (i == 4) {
            return :ITEM_4;
        } else if (i == 5) {
            return :ITEM_5;
        } else if (i == 6) {
            return :ITEM_6;
        } else if (i == 7) {
            return :ITEM_7;
        } else if (i == 8) {
            return :ITEM_8;
        } else if (i == 9) {
            return :ITEM_9;
        } else if (i == 10) {
            return :ITEM_10;
        } else if (i == 11) {
            return :ITEM_11;
        } else if (i == 12) {
            return :ITEM_12;
        } else if (i == 13) {
            return :ITEM_13;
        } else if (i == 14) {
            return :ITEM_14;
        } else if (i == 15) {
            return :ITEM_15;
        }
        return :ITEM_0;
    }
}

class SimilarCourseChooserDelegate extends Ui.MenuInputDelegate {
    var app as gimporterApp;

    function initialize() {
        MenuInputDelegate.initialize();
        app = $.getApp();
    }

    function toInt(sym as Symbol) as Number {
        if (sym.equals(:ITEM_0)) {
            return 0;
        } else if (sym.equals(:ITEM_1)) {
            return 1;
        } else if (sym.equals(:ITEM_2)) {
            return 2;
        } else if (sym.equals(:ITEM_3)) {
            return 3;
        } else if (sym.equals(:ITEM_4)) {
            return 4;
        } else if (sym.equals(:ITEM_5)) {
            return 5;
        } else if (sym.equals(:ITEM_6)) {
            return 6;
        } else if (sym.equals(:ITEM_7)) {
            return 7;
        } else if (sym.equals(:ITEM_8)) {
            return 8;
        } else if (sym.equals(:ITEM_9)) {
            return 9;
        } else if (sym.equals(:ITEM_10)) {
            return 10;
        } else if (sym.equals(:ITEM_11)) {
            return 11;
        } else if (sym.equals(:ITEM_12)) {
            return 12;
        } else if (sym.equals(:ITEM_13)) {
            return 13;
        } else if (sym.equals(:ITEM_14)) {
            return 14;
        } else if (sym.equals(:ITEM_15)) {
            return 15;
        }
        return 0;
    }

    function onMenuItem(item as Symbol) as Void {
        var index = toInt(item);
        app.launchSimilarCourse(index);
    }
}

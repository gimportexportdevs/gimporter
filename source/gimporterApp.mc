using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;

class gimporterApp extends App.AppBase {
    var tracks;
    var trackToStart;
    var acceptkey;
    var status;
    var mGPXorFIT;

    function initialize() {
        AppBase.initialize();
        tracks = null;
        acceptkey = true;
        status = "";
        mGPXorFIT = Ui.loadResource(Rez.Strings.GPXorFIT);
    }

    // onStart() is called on application start up
    function onStart(state) {
        loadTrackList();
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        return [ new gimporterView(), new gimporterDelegate() ];
    }

    function acceptKey() {
        return acceptkey;
    }

    function getStatus() {
        return status;
    }

    function getTracks() {
        return tracks;
    }

    function loadTrackList() {
        status = Rez.Strings.GettingTracklist;
        acceptkey = false;
        try {
            Comm.makeWebRequest("http://localhost:22222/dir.json", { "type" => mGPXorFIT },
                                {
                                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                                        :headers => {
                                        "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
                                    },
                                        :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                                             }, method(:onReceiveTracks)
                );
        } catch( ex ) {
            acceptkey = true;
            status = ex.getErrorMessage();
        }

        Ui.requestUpdate();

    }

    function onReceiveTracks(responseCode, data) {
        status = "";
        acceptkey = true;

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
            Ui.requestUpdate();
            return;
        }

        if (responseCode != 200) {
            System.println("data == null" + responseCode.toString());
            status = Rez.Strings.ConnectionFailed;
            Ui.requestUpdate();
            return;
        }

        if (!(data instanceof Toybox.Lang.Dictionary)) {
            System.println("data is not Dict");
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

    function loadTrackNum(index) {
        System.println("loadTrack: " + tracks[index].toString());

        // TODO: check hasKey
        var trackurl = tracks[index]["url"];
        trackToStart = tracks[index]["title"];

        status = Rez.Strings.Downloading;
        acceptkey = false;
        System.println("GPXorFIT: " + mGPXorFIT);

        try {
            if (mGPXorFIT.equals("FIT")) {
                System.println("Downloading FIT");
                Comm.makeWebRequest(trackurl, { "type" => "FIT" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT}, method(:onReceiveTrack) );
            } else {
                System.println("Downloading GPX");
                Comm.makeWebRequest(trackurl, { "type" => "GPX" }, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_GPX}, method(:onReceiveTrack) );
            }
        } catch( ex ) {
            acceptkey = true;
            status = Rez.Strings.DownloadNotSupported;
        }
        Ui.pushView(new gimporterView(), new gimporterPost(), Ui.SLIDE_IMMEDIATE);
        Ui.requestUpdate();
    }

    function onReceiveTrack(responseCode, data) {
        acceptkey = true;
        System.println("onReceiveTrack");

        if (responseCode == Comm.BLE_CONNECTION_UNAVAILABLE) {
            System.println("Bluetooth disconnected");
            status = Rez.Strings.BluetoothDisconnected;
        }
        else if (responseCode != 200) {
            System.println("Code: " + responseCode);
            status = Rez.Strings.DownloadFailed;
        }
        else if (data == null) {
            System.println("data == null");
            status = Rez.Strings.DownloadFailed;
        }
        else {
            System.println(data.toString());

            status = Rez.Strings.DownloadComplete;
            if (trackToStart.length() > 4) {
                var postfix = trackToStart.substring(trackToStart.length()-4, trackToStart.length()).toLower();
                if (postfix.equals(".fit") || postfix.equals(".gpx")) {
                    trackToStart = trackToStart.substring(0, trackToStart.length()-4);
                }
            }
            if (trackToStart.length() > 15) {
                trackToStart = trackToStart.substring(0, 15);
            }

            var cit = PC.getCourses();
            var course;
            while (true) {
                course = cit.next();
                if (course == null) {
                    break;
                }
                var coursename = course.getName();
                if (coursename.equals(trackToStart) || coursename.equals(trackToStart + "_course.fit")) {
                    Ui.popView(Ui.SLIDE_IMMEDIATE);
                    Ui.pushView(new TrackStart(), new TrackStartDelegate(coursename), Ui.SLIDE_IMMEDIATE);
                } else {
                    System.println(course.getName() + " != " + trackToStart);
                }
            }
        }
        Ui.requestUpdate();
        return;
    }
}

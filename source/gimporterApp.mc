using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;

class gimporterApp extends App.AppBase {
    var tracks;
    var acceptkey;
    var status;

    function initialize() {
        AppBase.initialize();
        tracks = null;
        acceptkey = true;
        status = "";
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

        Comm.makeWebRequest("http://localhost:22222/dir.json", null,
                            {
                                                                :method => Comm.HTTP_REQUEST_METHOD_GET,
                                                                :headers => {
                                                                        "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
                                                                },
                                    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                             }, method(:onReceiveTracks)
                                );
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

        status = Rez.Strings.Downloading;
        acceptkey = false;
        Comm.makeWebRequest(trackurl, null, {:method => Comm.HTTP_REQUEST_METHOD_GET,:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_FIT}, method(:onReceiveTrack) );
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
            status = Rez.Strings.DownloadComplete;
        }
        Ui.requestUpdate();
        return;
    }
}

using Toybox.WatchUi as Ui;
using Toybox.Communications as comm;

class importerView extends Ui.View {
        var tracks = null;
        var trackurl = null;

        function initialize() {
                View.initialize();
                tracks = null;
                trackurl = null;
        }

        // Load your resources here
        function onLayout(dc) {
                setLayout(Rez.Layouts.MainLayout(dc));
                System.println("onLayout");
                findDrawableById("t1").setText("T1");
                findDrawableById("t2").setText("T2");
                findDrawableById("t3").setText("T3");
                findDrawableById("t4").setText("T4");
        }

        function onReceive(responseCode, data) {
                if (responseCode == comm.BLE_CONNECTION_UNAVAILABLE) {
                        System.println("Bluetooth disconnected");
                        findDrawableById("t1").setText("Bluetooth disconnected");
                        Ui.requestUpdate();
                        return;
                }

                System.println("onReceive : ");
                //System.println(data);
                if (data == null) {
                        System.println("data == null" + responseCode.toString());
                        findDrawableById("t1").setText("null " + responseCode.toString());
                        Ui.requestUpdate();
                        return;
                }
                var tracks = data["tracks"];

                if (tracks == null) {
                        System.println("tracks == null");
                        findDrawableById("t2").setText("null");
                        Ui.requestUpdate();
                        return;
                }

                //System.println(tracks);
                if (tracks instanceof Toybox.Lang.Array) {
                        System.println("tracks == Array");
                } else {
                        System.println("tracks != Array");
                        findDrawableById("t2").setText("no Array");
                        Ui.requestUpdate();
                        return;
                }

/*
                for (var i = 0; i < tracks.size(); i++) {
                        System.println(tracks[i]["title"] + " - " + tracks[i]["url"]);
                }
*/
                if (tracks.size() > 0) {
                        findDrawableById("t1").setText(tracks[0]["title"]);
                        trackurl = tracks[0]["url"];
                }
                if (tracks.size() > 1) {
                        findDrawableById("t2").setText(tracks[1]["title"]);
                }
                if (tracks.size() > 2) {
                        findDrawableById("t3").setText(tracks[2]["title"]);
                }
                if (tracks.size() > 3) {
                        findDrawableById("t4").setText(tracks[3]["title"]);
                }
                Ui.requestUpdate();
        }

        // Called when this View is brought to the foreground. Restore
        // the state of this View and prepare it to be shown. This includes
        // loading resources into memory.
        function onShow() {
                System.println("onShow");
                comm.makeWebRequest("http://127.0.0.1:22222/dir.json", null, 
                                    {
                                            :method => comm.HTTP_REQUEST_METHOD_GET,
                                                    :headers => {
                                                    "Content-Type" => comm.REQUEST_CONTENT_TYPE_JSON
                                            },
                                                    :responseType => comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                                                             }, method(:onReceive) );
        }

        // Update the view
        function onUpdate(dc) {
                System.println("onUpdate");

                // Call the parent onUpdate function to redraw the layout
                View.onUpdate(dc);
        }

        // Called when this View is removed from the screen. Save the
        // state of this View here. This includes freeing resources from
        // memory.
        function onHide() {
        }

        function loadTrack() {
                System.println("loadTrack");

                if (trackurl == null) {
                        return;
                }
                var tracktype = trackurl.substring(trackurl.length()-3, trackurl.length());
                findDrawableById("t2").setText(tracktype);
                Ui.requestUpdate();

                findDrawableById("t3").setText("Downloading FIT");
                Ui.requestUpdate();
                comm.makeWebRequest(trackurl, null,
                                    {
                                            :method => comm.HTTP_REQUEST_METHOD_GET,
                                                    :responseType => comm.HTTP_RESPONSE_CONTENT_TYPE_FIT
                                                    }, method(:onReceiveTrack) );
        }
        function onReceiveTrack(responseCode, data) {
                System.println("onReceiveTrack");
                if (responseCode == comm.BLE_CONNECTION_UNAVAILABLE) {
                        System.println("Bluetooth disconnected");
                        findDrawableById("t1").setText("Bluetooth disconnected");
                        Ui.requestUpdate();
                        return;
                }
                System.println("Code:"+responseCode);
                if (responseCode == 200) {
                
	                if (data == null) {
	                        System.println("data == null");
	                        findDrawableById("t3").setText("null " + responseCode.toString());
	                } else {
	                        System.println(data);
	                        //System.println(data["args"]);
	                        if (data instanceof Toybox.Lang.Array) {
	                        	for( var i = 0; i < data.size(); i++ ) {
			                        System.println("data[" + i.toString() + "] = " + data[i].toString());                	
	                        	}
	                        } else if (data instanceof Toybox.Lang.Dictionary) {
	                        	keys = data.keys();
	                        	
	                        	for( var i = 0; i < keys.size(); i++ ) {
			                        System.println("data['" + keys[i].toString() + "']");                	
	                        	}
	                        //} else if (data instanceof Toybox.Lang.String) {
	                        }
	                        findDrawableById("t3").setText("Download finished");
	                }
                } else {
                    findDrawableById("t2").setText(responseCode.toString());
                    findDrawableById("t3").setText("Download failed");
                }
                Ui.requestUpdate();
                return;
        }
}

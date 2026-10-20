import Toybox.Lang;
import Toybox.Test;

using Toybox.Communications as Comm;
using Toybox.PersistedContent as PC;

// Stand-ins for PersistedContent objects: the real ones only come from the
// device, but searchCourse()/findWaypoint() only call next() and getName().
(:test)
class FakeContent {
    var mName as String;
    var mId as Number;

    function initialize(name as String, id as Number) {
        mName = name;
        mId = id;
    }

    function getName() as String {
        return mName;
    }

    function getId() as Number {
        return mId;
    }
}

(:test)
class FakeIterator {
    var mItems as Array<FakeContent>;
    var mPos as Number = 0;

    function initialize(names as Array<String>) {
        mItems = [] as Array<FakeContent>;
        for (var i = 0; i < names.size(); i++) {
            // ids 101, 102, ... so they are not confused with indices
            mItems.add(new FakeContent(names[i], 101 + i));
        }
    }

    function next() as FakeContent? {
        if (mPos >= mItems.size()) {
            return null;
        }
        mPos++;
        return mItems[mPos - 1];
    }
}

// Helpers live in a module: a (:test) function at top level would be run as a test.
(:test)
module TestHelpers {
    function fakeIterator(names as Array<String>) as PC.Iterator {
        return new FakeIterator(names) as Object as PC.Iterator;
    }

    // "" for no content, so the result can go straight into assertEqual()
    function nameOf(content as Object?) as String {
        return content == null ? "" : (content as FakeContent).getName();
    }
}

(:test)
function testItemSymbolsRoundTrip(logger as Test.Logger) as Boolean {
    for (var i = 0; i < ITEM_SYMBOLS.size(); i++) {
        if ($.symToItem($.itemToSym(i)) != i) {
            logger.debug("round trip failed for " + i);
            return false;
        }
    }
    return true;
}

(:test)
function testCommErrorString(logger as Test.Logger) as Boolean {
    Test.assertEqual($.commErrorString(Comm.BLE_CONNECTION_UNAVAILABLE, Rez.Strings.DownloadFailed),
        Rez.Strings.BluetoothDisconnected);
    Test.assertEqual($.commErrorString(Comm.STORAGE_FULL, Rez.Strings.DownloadFailed),
        Rez.Strings.StorageFull);
    // Anything without a specific message falls back to the caller's default
    Test.assertEqual($.commErrorString(404, Rez.Strings.DownloadFailed), Rez.Strings.DownloadFailed);
    return true;
}

(:test)
function testIsLocation(logger as Test.Logger) as Boolean {
    Test.assert($.isLocation({ "title" => "Dom", "url" => "Dom.gpx", "lat" => "48.2084000", "lon" => "16.3731000" }));
    // a course entry
    Test.assert(!$.isLocation({ "title" => "Tour", "url" => "Tour.gpx" }));
    // numbers would have lost precision; only strings are accepted
    Test.assert(!$.isLocation({ "title" => "Dom", "url" => "Dom.gpx", "lat" => 48.2084, "lon" => 16.3731 }));
    Test.assert(!$.isLocation({ "title" => "Dom", "url" => "Dom.gpx", "lat" => "48.2084000" }));
    return true;
}

(:test)
function testFindWaypointExactWins(logger as Test.Logger) as Boolean {
    var wp = $.findWaypoint(TestHelpers.fakeIterator(["Stephans", "Stephansdom", "Other"]), "Stephansdom");
    Test.assertEqual(TestHelpers.nameOf(wp), "Stephansdom");
    return true;
}

(:test)
function testFindWaypointShortenedName(logger as Test.Logger) as Boolean {
    // the device stored the name cut to 15 characters
    var wp = $.findWaypoint(TestHelpers.fakeIterator(["Other", "Wiener Riesenra"]), "Wiener Riesenrad");
    Test.assertEqual(TestHelpers.nameOf(wp), "Wiener Riesenra");
    return true;
}

(:test)
function testFindWaypointNone(logger as Test.Logger) as Boolean {
    // (Test.assertEqual(x, null) cannot be used: it calls x.equals())
    Test.assert($.findWaypoint(TestHelpers.fakeIterator(["Other"]), "Stephansdom") == null);
    Test.assert($.findWaypoint(TestHelpers.fakeIterator([] as Array<String>), "Stephansdom") == null);
    // a longer stored name is not a match for the shorter requested one
    Test.assert($.findWaypoint(TestHelpers.fakeIterator(["Stephansdom"]), "Stephans") == null);
    return true;
}

(:test)
function testNormalizeName(logger as Test.Logger) as Boolean {
    var app = new gimporterApp();
    Test.assertEqual(app.normalizeName("Tour_course.fit"), "Tour");
    Test.assertEqual(app.normalizeName("Tour.fit"), "Tour");
    Test.assertEqual(app.normalizeName("Tour.gpx"), "Tour");
    Test.assertEqual(app.normalizeName("Tour"), "Tour");
    // too short to carry a suffix
    Test.assertEqual(app.normalizeName(".gpx"), ".gpx");
    return true;
}

(:test)
function testSearchCoursePartialMatches(logger as Test.Logger) as Boolean {
    var app = new gimporterApp();
    app.trackToStart = "Tour.gpx";
    // course names longer than the track name are only "similar"
    Test.assert(app.searchCourse(TestHelpers.fakeIterator(["Tour de Wien", "Other", "Tourist"])));
    var similar = app.getSimilarCourses() as Array<Object>;
    Test.assert(similar != null);
    Test.assertEqual(similar.size(), 2);
    Test.assertEqual(TestHelpers.nameOf(similar[0]), "Tour de Wien");
    Test.assertEqual(TestHelpers.nameOf(similar[1]), "Tourist");
    return true;
}

(:test)
function testSearchCourseNoMatch(logger as Test.Logger) as Boolean {
    var app = new gimporterApp();
    app.trackToStart = "Tour.gpx";
    Test.assert(!app.searchCourse(TestHelpers.fakeIterator(["Other", "Something"])));
    Test.assert(app.getSimilarCourses() == null);

    app.trackToStart = null;
    Test.assert(!app.searchCourse(TestHelpers.fakeIterator(["Tour"])));
    return true;
}

(:test)
function testLocationMessage(logger as Test.Logger) as Boolean {
    var now = 1790000000;
    var msg = { "type" => "location", "title" => "Dom", "lat" => "48.2084000", "lon" => "16.3731000", "time" => now - 60 };
    Test.assert($.isLocationMessage(msg, now));
    // small clock difference between phone and watch
    msg["time"] = now + 120;
    Test.assert($.isLocationMessage(msg, now));
    return true;
}

(:test)
function testLocationMessageStale(logger as Test.Logger) as Boolean {
    var now = 1790000000;
    // shared yesterday, app opened only now
    var msg = { "type" => "location", "title" => "Dom", "lat" => "48.2084000", "lon" => "16.3731000", "time" => now - 86400 };
    Test.assert(!$.isLocationMessage(msg, now));
    msg["time"] = now + 3600;
    Test.assert(!$.isLocationMessage(msg, now));
    return true;
}

(:test)
function testLocationMessageMalformed(logger as Test.Logger) as Boolean {
    var now = 1790000000;
    Test.assert(!$.isLocationMessage(22222, now));  // a port reply
    Test.assert(!$.isLocationMessage(null, now));
    Test.assert(!$.isLocationMessage({ "type" => "other", "title" => "Dom", "lat" => "1.0", "lon" => "2.0", "time" => now }, now));
    Test.assert(!$.isLocationMessage({ "type" => "location", "lat" => "1.0", "lon" => "2.0", "time" => now }, now));
    Test.assert(!$.isLocationMessage({ "type" => "location", "title" => "Dom", "lat" => 1.0, "lon" => 2.0, "time" => now }, now));
    Test.assert(!$.isLocationMessage({ "type" => "location", "title" => "Dom", "lat" => "1.0", "lon" => "2.0" }, now));
    return true;
}

(:test)
function testAppendContent(logger as Test.Logger) as Boolean {
    var items = [] as Array;
    $.appendContent(items, "course", TestHelpers.fakeIterator(["Tour", "Runde"]));
    $.appendContent(items, "waypoint", TestHelpers.fakeIterator(["Dom"]));
    Test.assertEqual(items.size(), 3);
    var first = items[0] as Array<Object>;
    Test.assertEqual(first[0], "course");
    Test.assertEqual(first[1], "Tour");
    Test.assertEqual(first[2], 101);
    var last = items[2] as Array<Object>;
    Test.assertEqual(last[0], "waypoint");
    Test.assertEqual(last[1], "Dom");
    return true;
}

(:test)
function testAppendContentIsCapped(logger as Test.Logger) as Boolean {
    var names = [] as Array<String>;
    for (var i = 0; i < MAX_CONTENT_ITEMS + 5; i++) {
        names.add("T" + i);
    }
    var items = [] as Array;
    $.appendContent(items, "course", TestHelpers.fakeIterator(names));
    Test.assertEqual(items.size(), MAX_CONTENT_ITEMS);
    return true;
}

(:test)
function testFindContentById(logger as Test.Logger) as Boolean {
    Test.assertEqual(TestHelpers.nameOf($.findContentById(TestHelpers.fakeIterator(["A", "B", "C"]), 102)), "B");
    Test.assert($.findContentById(TestHelpers.fakeIterator(["A"]), 999) == null);
    return true;
}

(:test)
function testDeleteRequestItems(logger as Test.Logger) as Boolean {
    var now = 1790000000;
    var items = $.deleteRequestItems({ "type" => "delete", "items" => [["course", 101], ["waypoint", 7]], "time" => now }, now);
    Test.assert(items != null);
    Test.assertEqual((items as Array).size(), 2);
    // queued for hours while the app was closed
    Test.assert($.deleteRequestItems({ "type" => "delete", "items" => [["course", 101]], "time" => now - 86400 }, now) == null);
    // malformed entries reject the whole request
    Test.assert($.deleteRequestItems({ "type" => "delete", "items" => [["course", "101"]], "time" => now }, now) == null);
    Test.assert($.deleteRequestItems({ "type" => "delete", "items" => [["course"]], "time" => now }, now) == null);
    Test.assert($.deleteRequestItems({ "type" => "delete", "time" => now }, now) == null);
    return true;
}

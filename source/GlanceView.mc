import Toybox.Lang;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as GFX;

// Glance shown in the widget carousel on glance-capable devices; tapping it
// launches the app. Keep this lean: everything (:glance) annotated is loaded
// into the glance scope, which has a small memory budget.
(:glance)
class gimporterGlanceView extends Ui.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as GFX.Dc) as Void {
        var h = dc.getHeight();
        dc.setColor(GFX.COLOR_WHITE, GFX.COLOR_TRANSPARENT);
        dc.drawText(0, h / 3, GFX.FONT_GLANCE,
                    Ui.loadResource(Rez.Strings.AppName) as String,
                    GFX.TEXT_JUSTIFY_LEFT | GFX.TEXT_JUSTIFY_VCENTER);
        dc.setColor(GFX.COLOR_LT_GRAY, GFX.COLOR_TRANSPARENT);
        dc.drawText(0, 2 * h / 3, GFX.FONT_GLANCE,
                    (Ui.loadResource(Rez.Strings.GPXorFIT) as String) + " " +
                    (Ui.loadResource(Rez.Strings.AppVersion) as String),
                    GFX.TEXT_JUSTIFY_LEFT | GFX.TEXT_JUSTIFY_VCENTER);
    }
}

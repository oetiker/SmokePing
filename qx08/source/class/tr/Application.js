/* ************************************************************************

   Copyright: OETIKER+PARTNER AG

   License: Gnu GPL Verrsion 3

   Authors: Tobias Oetiker <tobi@oetiker.ch>

************************************************************************ */

/* ************************************************************************

#asset(tr/*)

************************************************************************ */

/**
 * This is the main application class of your custom application "qx08"
 */
qx.Class.define("tr.Application", {
    extend : qx.application.Standalone,

    members : {
        /**
         * This method contains the initial application code and gets called
         * during startup of the application
         *
         * @type member
         * @return {void} 
         */
        main : function() {
            // Call super class
            this.base(arguments);

            // Enable logging in debug variant
            if (qx.core.Variant.isSet("qx.debug", "on")) {
                // support native logging capabilities, e.g. Firebug for Firefox
                qx.log.appender.Native;

                // support additional cross-browser console. Press F7 to toggle visibility
                qx.log.appender.Console;
            }

            // if we run with a file:// url make sure
            // the app finds the Tr service (tr.cgi)
            tr.Server.getInstance().setLocalUrl('http://localhosth/~oetiker/tr/');

            // Document is the application root
            var root = new qx.ui.container.Composite(new qx.ui.layout.VBox());

            this.getRoot().add(root, {
                left   : 0,
                top    : 0,
                right  : 0,
                bottom : 0
            });

            root.set({ margin : 10 });
            var top = new qx.ui.container.Composite(new qx.ui.layout.HBox().set({ alignY : 'top' }));
            var title = new tr.ui.Link('SmokeTrace 2.4.2', 'http://oss.oetiker.ch/smokeping/', '#b0b0b0', '20px bold sans-serif');

            top.add(title);
            top.add(new qx.ui.core.Spacer(), { flex : 1 });
            top.add(new tr.ui.ActionButton());
            root.add(top);

            var trace = new tr.ui.TraceTable();
            root.add(trace, { flex : 1 });

            root.add(new tr.ui.Footer(this.tr("SmokeTrace is part of the of the SmokePing suite created by Tobi Oetiker, Copyright 2008."), 'http://oss.oetiker.ch/smokeping/'));

            var cfgwin = new tr.ui.Config();

            this.getRoot().add(cfgwin, {
                left : 30,
                top  : 30
            });

            qx.event.message.Bus.subscribe('tr.config', function(e) {
                switch(e.getData())
                {
                    case 'open':
                        cfgwin.open();
                        break;

                    case 'cancel':
                        case 'ok':
                            cfgwin.close();
                            break;
                    }
                });
            }
        }
    });
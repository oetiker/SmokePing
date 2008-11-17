/* ************************************************************************
   Copyright: 2008, OETIKER+PARTNER AG
   License: GPL
   Authors: Tobias Oetiker
   $Id: $
* ************************************************************************ */

/*
#asset(tr/*)
*/

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
                qx.log.appender.Native;
                qx.log.appender.Console;
            }

            // if we run with a file:// url make sure
            // the app finds the Tr service (tr.cgi)
            tr.Server.getInstance().setLocalUrl('http://localhost/~oetiker/tr/');

            this.getRoot().add(new tr.ui.CopyBuffer(), {
                left : 0,
                top  : 0
            });

            this.getRoot().add(new tr.ui.Error(), {
                left : 0,
                top  : 0
            });

            this.getRoot().add(new tr.ui.Config(), {
                left : 0,
                top  : 0
            });

            this.getRoot().add(new tr.ui.Link('SmokeTrace 2.4.2', 'http://oss.oetiker.ch/smokeping/', '#b0b0b0', '17px bold sans-serif'), {
                right : 7,
                top   : 5
            });

            // Document is the application root
            var root = new qx.ui.container.Composite(new qx.ui.layout.VBox());
            root.setPadding(5);

            this.getRoot().add(root, {
                left   : 0,
                top    : 0,
                right  : 0,
                bottom : 0
            });

            var tabs = new qx.ui.tabview.TabView();
            root.add(tabs, { flex : 1 });

            root.add(new tr.ui.Footer(this.tr("SmokeTrace is part of the of the SmokePing suite created by Tobi Oetiker, Copyright 2008."), 'http://oss.oetiker.ch/smokeping/'));

            tabs.add(new tr.ui.TraceTab());
            this.__handles = {};
            qx.event.message.Bus.subscribe('add_handle',this.__add_handle,this);
        },

        __handles: null,
        __handle_count: 0,

        __add_handle: function(m){
            var handle = m.getData();
            this.__handles[handle]=0;
            if (this.__handle_count == 0){
               this.__run_poller();
            }
        },
        __run_poller: function(){        
            var that = this;
            tr.Server.getInstance().callAsync(
                function(ret,exc,id){that.__process_input(ret,exc,id);},'poll',this.__handles
            );
        },
        __process_input: function(ret,exc,id){
            if (exc == null) {
                for (var hand in ret){
                    this.info('got '+hand);
                    if (hand == 'handles'){
                        this.__handles = ret[hand];
                    }
                    if (ret[hand]['data']){
                        qx.event.message.Bus.dispatch(hand+'::data', ret[hand]['data']);
                    }
                    if (ret[hand]['type']){
                        qx.event.message.Bus.dispatch(hand+'::status', {type : ret[hand]['type'],
                                                                        msg  : ret[hand]['msg']  });
                    }
                };
            }
            else {
                qx.event.message.Bus.dispatch('error', [ this.tr("Server Error"), '' + exc ]);
            }
            this.__handle_count = 0;
            for(var i in this.__handles){
                this.__handle_count ++;
            };
            if (this.__hanlde_count > 0){
                qx.event.Timer.once(this.__run_poller,this,this.__interval);
            }
        }
    }
});

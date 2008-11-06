/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * a widget showing the Tr graph overview
 */
qx.Class.define('tr.ui.ActionButton', {
    extend : qx.ui.container.Composite,




    /*
                *****************************************************************************
                   CONSTRUCTOR
                *****************************************************************************
                */

    construct : function() {
        this.base(arguments, new qx.ui.layout.VBox);

        //    this.set({ alignX : 'left' });
        //    return this;
        var hbox = new qx.ui.container.Composite(new qx.ui.layout.HBox().set({
            alignY  : 'middle',
            spacing : 5
        }));

        var lab1 = new qx.ui.basic.Label(this.tr("Host"));
        lab1.set({ paddingRight : 6 });
        hbox.add(lab1);
        var host = new qx.ui.form.TextField();

        host.set({
            width   : 200,
            padding : 1
        });

        hbox.add(host);
        this.__host = host;
        var lab2 = new qx.ui.basic.Label(this.tr("Delay"));

        lab2.set({
            paddingRight : 6,
            paddingLeft  : 12
        });

        hbox.add(lab2);

        var delay = new qx.ui.form.Spinner(0, 2, 60);

        delay.set({ width : 45 });
        hbox.add(delay);
        this.__delay = delay;

        var lab3 = new qx.ui.basic.Label(this.tr("Rounds"));

        lab3.set({
            paddingRight : 6,
            paddingLeft  : 12
        });

        hbox.add(lab3);
        var rounds = new qx.ui.form.Spinner(0, 20, 200);

        rounds.set({ width : 45 });

        hbox.add(rounds);
        this.__rounds = rounds;

        var button = new qx.ui.form.Button('');
        this.__button = button;

        button.set({
            marginLeft : 10,
            width      : 60,
            padding    : 2,
            center     : true
        });

        hbox.add(button);

        var config = new qx.ui.form.Button(this.tr("Config ..."));
        hbox.add(config);

        config.addListener('execute', function(e) {
            qx.event.message.Bus.dispatch('tr.config', 'open');
        });

        this.add(hbox);

        var info = new qx.ui.basic.Atom();

        info.set({
            marginTop       : 3,
            padding         : 3,
            textColor       : 'red',
            backgroundColor : '#f0f0f0',
            visibility      : 'hidden'
        });

        qx.event.message.Bus.subscribe('tr.info', this.__set_info, this);
        this.add(info);
        this.__info = info;

        qx.event.message.Bus.subscribe('tr.status', this.__set_status, this);
        qx.event.message.Bus.dispatch('tr.status', 'stopped');

        var start_trace = function(event) {
            qx.event.message.Bus.dispatch('tr.cmd', {
                action : button.getUserData('action'),
                host   : host.getValue(),
                delay  : delay.getValue(),
                rounds : rounds.getValue()
            });
        };

        host.addListener('keydown', function(e) {
            if (e.getKeyIdentifier() == 'Enter') {
                start_trace();
            }
        });

        // host.addListener('execute', start_trace);
        button.addListener('execute', start_trace);

        var history = qx.bom.History.getInstance();

        var history_action = function(event) {
            var targ = event.getData();
            host.setValue(targ);
            history.addToHistory(targ, 'SmokeTrace to ' + targ);
            start_trace();
        };

        history.addListener('request', history_action);

        // if we got called with a host on the commandline
        var initial_host = qx.bom.History.getInstance().getState();

        if (initial_host) {
            host.setValue(initial_host);
            history.addToHistory(initial_host, 'SmokeTrace to ' + initial_host);

            // dispatch this task once all the initializations are done
            qx.event.Timer.once(start_trace, this, 0);
        }
    },

    members : {
        __host : null,
        __delay : null,
        __rounds : null,
        __button : null,
        __info : null,


        /**
         * TODOC
         *
         * @type member
         * @param e {Event} TODOC
         * @return {void} 
         */
        __set_info : function(e) {
            this.__info.set({
                label      : e.getData(),
                visibility : 'visible'
            });
        },


        /**
         * TODOC
         *
         * @type member
         * @param m {var} TODOC
         * @return {void} 
         */
        __set_status : function(m) {
            var host = this.__host;
            var rounds = this.__rounds;
            var delay = this.__delay;
            var button = this.__button;
            var action = button.getUserData('action');

            // this.debug(m.getData());
            switch(m.getData())
            {
                case 'starting':
                    if (action == 'go') {
                        button.setLabel(this.tr("Starting"));
                        this.__info.setVisibility('hidden');

                        // border:'dark-shadow',
                        button.setEnabled(false);
                        host.setEnabled(false);
                        rounds.setEnabled(false);
                        delay.setEnabled(false);
                    }

                    break;

                case 'stopping':
                    if (action == 'stop') {
                        button.setLabel(this.tr("Stopping"));
                        button.setEnabled(false);
                        host.setEnabled(false);
                        rounds.setEnabled(false);
                        delay.setEnabled(false);
                    }

                    break;

                case 'stopped':
                    button.setUserData('action', 'go');
                    button.setLabel(this.tr("Go"));
                    button.setEnabled(true);
                    host.setEnabled(true);
                    rounds.setEnabled(true);
                    delay.setEnabled(true);
                    break;

                case 'started':
                    button.setUserData('action', 'stop');
                    button.setLabel(this.tr("Stop"));
                    button.setEnabled(true);
                    host.setEnabled(false);
                    rounds.setEnabled(false);
                    delay.setEnabled(false);
                    break;

                default:
                    this.error('Unknown Status Message: ' + m.getData());
            }
        }
    }
});
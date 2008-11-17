/* ************************************************************************
#module(Tr)
#asset(qx/icon/${qx.icontheme}/22/actions/dialog-apply.png)
#asset(qx/icon/${qx.icontheme}/22/actions/dialog-close.png)

************************************************************************ */

/**
 * show the config options for traceroute as defined by the server
 */
qx.Class.define('tr.ui.Config', {
    extend : qx.ui.window.Window,

    construct : function() {
        this.base(arguments, this.tr("Traceroute Configuration"));
        var layout = new qx.ui.layout.Grid(3, 5);
        layout.setColumnAlign(0, 'right', 'middle');
        layout.setColumnAlign(1, 'left', 'middle');
        layout.setColumnWidth(0, 140);
        layout.setColumnWidth(1, 140);

        this.setLayout(layout);

        this.set({
            allowMaximize : false,
            allowMinimize : false,
            modal         : true,
            resizable     : false,
            showMaximize  : false,
            showMinimize  : false
        });

        var that = this;

        var create_config = function(retval, exc, id) {
            if (exc == null) {
                that.__create_config(retval);
            } else {
                qx.event.message.Bus.dispatch('error', [ that.tr("Server Error"), '' + exc ]);
            }
        };

        tr.Server.getInstance().callAsync(create_config, 'get_config');

        qx.event.message.Bus.subscribe('config', function(e) {
            this.__task = e.getData();
            this.__seed();
            this.center();
            this.open();
        },
        this);
    },

    members : {
        __task : null,
        __setters : null,


        /**
         * Load configuration values into dialog. If no values are provided,
         * the default values get loaded.
         *
         * @type member
         * @return {void}
         */
        __seed : function() {
            for (var key in this.__setters) {
                this.info(key+': '+this.__task[key])
                this.__setters[key](this.__task[key]);
            }
        },


        /**
         * TODOC
         *
         * @type member
         * @param data {var} TODOC
         * @return {void}
         */
        __create_config : function(data) {
            var entries = data.length;
            var status = {};
            var setters = {};
            this.__setters = setters;

            var r = 0;
            var that = this;

            for (var k=0; k<entries; k++) {
                (function() {
                    for (var check in
                    {
                        'default' : 0,
                        'label'   : 0,
                        'type'    : 0
                    }) {
                        if (data[k][check] == undefined) {
                            that.debug('Skipping ' + data[k] + ' since there is no ' + check);
                            // exit from function is like 'next'
                            return;
                        }
                    }

                    var def = data[k]['default'];
                    var widget;
                    var pick;
                    var items;
                    var c;

                    that.add(new qx.ui.basic.Label(data[k]['label']).set({ marginRight : 5 }), {
                        row    : r,
                        column : 0
                    });

                    switch(data[k]['type'])
                    {
                        case 'spinner':
                            widget = new qx.ui.form.Spinner(data[k]['min'], def, data[k]['max']);
                            status[data[k]['key']] = function() {
                                return widget.getValue();
                            };

                            setters[data[k]['key']] = function(value) {
                                widget.setValue(value == undefined ? def : value);
                            };

                            break;

                        case 'select':
                            widget = new qx.ui.form.SelectBox();
                            status[data[k]['key']] = function() {
                                return widget.getValue();
                            };

                            setters[data[k]['key']] = function(value) {
                                widget.setValue(value == undefined ? def : value);
                            };

                            pick = data[k]['pick'];
                            items = pick.length;

                            for (c=0; c<items; c+=2) {
                                widget.add(new qx.ui.form.ListItem(pick[c + 1], null, pick[c]));
                            }

                            break;

                        case 'boolean':
                            widget = new qx.ui.form.CheckBox();
                            status[data[k]['key']] = function() {
                                return widget.getChecked();
                            };

                            setters[data[k]['key']] = function(value) {
                                widget.setChecked(value == undefined ? def > 0 : value > 0);
                            };

                            break;
                    }

                    that.add(widget, {
                        row    : r,
                        column : 1
                    });

                    r++;
                })();
            }

            var ok = new qx.ui.form.Button(this.tr("Apply")).set({
                marginTop  : 10,
                marginLeft : 40
            });

            ok.addListener('execute', function(e) {
                for (var key in status) {
                    that.__task[key] = status[key]();
                }

                that.close();
            });

            this.add(ok, {
                row    : r,
                column : 0
            });

            var cancel = new qx.ui.form.Button(this.tr("Reset")).set({
                marginTop   : 10,
                marginRight : 30
            });

            cancel.addListener('execute', function(e) {
                for (var key in setters) {
                    setters[key]();
                }
            });

            this.add(cancel, {
                row    : r,
                column : 1
            });
        }
    }
});

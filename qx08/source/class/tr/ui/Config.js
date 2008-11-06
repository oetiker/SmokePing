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




    /*
       *****************************************************************************
       CONSTRUCTOR
       *****************************************************************************
       */

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

        var self = this;

        var create_config = function(retval, exc, id) {
            if (exc == null) {
                self.__create_config(retval);
            } else {
                self.error(exc);
            }
        };

        tr.Server.getInstance().callAsync(create_config, 'get_config');
    },

    members : {
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
            var setdef = {};
            var r = 0;
            var self = this;

            for (var k=0; k<entries; k+=2) {
                (function() {* // force local scoping
                    var v = k + 1;

                    for (var check in
                    {
                        'default' : 0,
                        'label'   : 0,
                        'type'    : 0
                    }) {
                        if (data[v][check] == undefined) {
                            self.debug('Skipping ' + data[k] + ' since there is no ' + check);
                            return ;* // we are inside a function, so we return instead of continue
                        }
                    }

                    var def = data[v]['default'];
                    var widget;
                    var pick;
                    var items;
                    var check;
                    var c;

                    self.add(new qx.ui.basic.Label(data[v]['label']).set({ marginRight : 5 }), {
                        row    : r,
                        column : 0
                    });

                    switch(data[v]['type'])
                    {
                        case 'spinner':
                            widget = new qx.ui.form.Spinner(data[v]['min'], def, data[v]['max']);
                            status[data[k]] = function() {
                                return widget.getValue();
                            };

                            setdef[data[k]] = function() {
                                widget.setValue(def);
                            };

                            break;

                        case 'select':
                            widget = new qx.ui.form.SelectBox();
                            status[data[k]] = function() {
                                return widget.getValue();
                            };

                            setdef[data[k]] = function() {
                                widget.setValue(def);
                            };

                            pick = data[v]['pick'];
                            items = pick.length;

                            for (c=0; c<items; c+=2) {
                                widget.add(new qx.ui.form.ListItem(pick[c + 1], null, pick[c]));
                            }

                            break;

                        case 'boolean':
                            widget = new qx.ui.form.CheckBox();
                            status[data[k]] = function() {
                                return widget.getChecked();
                            };

                            setdef[data[k]] = function() {
                                widget.setChecked(def > 0);
                            };

                            break;
                    }

                    self.add(widget, {
                        row    : r,
                        column : 1
                    });

                    r++;
                })();

            }* // this is the rest of the scoping trick

            for (var key in setdef) {
                setdef[key]();
            }

            var ok = new qx.ui.form.Button(this.tr("Apply")).set({
                marginTop  : 10,
                marginLeft : 20
            });

            ok.addListener('execute', function(e) {
                var config = {};

                for (var key in status) {
                    config[key] = status[key]();
                }

                self.close();
                qx.event.message.Bus.dispatch('tr.setup', config);
            });

            this.add(ok, {
                row    : r,
                column : 0
            });

            var cancel = new qx.ui.form.Button(this.tr("Reset")).set({
                marginTop   : 10,
                marginRight : 20
            });

            cancel.addListener('execute', function(e) {
                for (var key in setdef) {
                    setdef[key]();
                }
            });

            this.add(cancel, {
                row    : r,
                column : 1
            });
        }
    }
});
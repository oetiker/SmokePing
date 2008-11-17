/* ************************************************************************
   Copyright: 2008, OETIKER+PARTNER AG
   License: GPL
   Authors: Tobias Oetiker
   $Id: $
* ************************************************************************ */

/**
 * a widget showing the Tr target tree
 */
qx.Class.define('tr.ui.TraceTable', {
    extend : qx.ui.table.Table,

    construct : function() {
        var tableModel = new qx.ui.table.model.Simple();
        this.__tableModel = tableModel;

        tableModel.setColumns([ this.tr("Hop"), this.tr("Host"), this.tr("Ip"), this.tr("Loss [%]"), this.tr("Sent"), this.tr("Last [ms]"), this.tr("Avg [ms]"), this.tr("Best [ms]"), this.tr("Worst [ms]"), this.tr("StDev [ms]") ]);

        var custom = {
            tableColumnModel : function(obj) {
                return new qx.ui.table.columnmodel.Resize(obj);
            }
        };

        this.base(arguments, tableModel, custom);

        this.set({
            decorator              : 'main',
            showCellFocusIndicator : false,
            statusBarVisible       : false
        });

        var tcm = this.getTableColumnModel();
        this.__tcm = tcm;

        tcm.setDataCellRenderer(0, new tr.ui.Cellrenderer(1));
        tcm.setDataCellRenderer(3, new tr.ui.Cellrenderer(0, ' %'));
        tcm.setDataCellRenderer(4, new tr.ui.Cellrenderer(0));

        var render_ms = new tr.ui.Cellrenderer(1);

        for (var i=5; i<10; i++) {
            tcm.setDataCellRenderer(i, render_ms);
        }

        // Obtain the behavior object to manipulate
        var resizeBehavior = tcm.getBehavior();

        // This uses the set() method to set all attriutes at once; uses flex
        resizeBehavior.set(0, { width : '2*' });
        resizeBehavior.set(1, { width : '9*' });
        resizeBehavior.set(2, { width : '5*' });

        for (var i=3; i<10; i++) {
            resizeBehavior.set(i, { width : '3*' });
        }

    },

    members : {
        __handle : null,
        __data : null,
        __delay : null,
        __tableModel : null,
        __tcm : null,


        /**
         * TODOC
         *
         * @type member
         * @return {var} TODOC
         */
        __make_empty_row : function() {
            return ([ undefined, undefined, undefined, 0, 0, undefined, undefined, undefined, undefined, undefined, 0, 0, 0 ]);
        },


        /**
         * TODOC
         *
         * @type member
         * @return {void} 
         */
        __stop_table : function() {
            var tableModel = this.__tableModel;

            for (var i=0; i<10; i++) {
                tableModel.setColumnSortable(i, true);
            }

            qx.event.message.Bus.dispatch('tr.status', 'stopped');
            this.__handle = undefined;
        },


        /**
         * TODOC
         *
         * @type member
         * @param retval {var} TODOC
         * @param exc {Exception} TODOC
         * @param id {var} TODOC
         * @return {void} 
         */
        __fill_table : function(retval, exc, id) {
            var f_host = 1;
            var f_ip = 2;
            var f_loss = 3;
            var f_snt = 4;
            var f_last = 5;
            var f_avg = 6;
            var f_best = 7;
            var f_worst = 8;
            var f_stdev = 9;
            var f_cnt = 10;
            var f_sum = 11;
            var f_sqsum = 12;
            var that = this;

            if (exc == null) {
                if (this.__handle == undefined) {
                    qx.event.message.Bus.dispatch('tr.status', 'started');
                }

                this.__handle = retval['handle'];
                var tableModel = this.__tableModel;
                var lines = retval['output'].length;
                var data = this.__data;
                var sleep = 0;

                for (var i=0; i<lines; i++) {
                    sleep = 0;
                    var hop = retval['output'][i][0];

                    if (hop == 'SLEEP') {
                        sleep = retval['output'][i][1];
                        continue;
                    }
                    else if (hop == 'INFO') {
                        qx.event.message.Bus.dispatch('tr.info', retval['output'][i][1]);
                        continue;
                    }

                    var host = retval['output'][i][1];
                    var ip = retval['output'][i][2];
                    var value = retval['output'][i][3];
                    var ii = 0;
                    var max = data.length;

                    while (true) {
                        if (ii == max) {
                            break;
                        }

                        if (Math.floor(data[ii][0]) > hop) {
                            break;
                        }

                        if (Math.floor(data[ii][0]) == hop) {
                            if (ip == undefined) {
                                break;
                            }

                            if (ip == data[ii][2]) {
                                break;
                            }
                        }

                        ii++;
                    }

                    if (ii == max || Math.floor(data[ii][0]) > hop) {
                        if (ii > 0 && Math.floor(data[ii - 1][0]) == hop) {
                            hop = data[ii - 1][0] + 0.1;
                        }

                        data.splice(ii, 0, this.__make_empty_row());
                        data[ii][0] = hop;
                    }

                    var drow = data[ii];

                    if (drow[f_host] == undefined && host != undefined) {
                        drow[f_host] = host;
                    }

                    if (drow[f_ip] == undefined && ip != undefined) {
                        drow[f_ip] = ip;
                    }

                    drow[f_snt]++;
                    drow[f_last] = value;

                    if (value != undefined) {
                        var best = drow[f_best];

                        if (best == undefined || best > value) {
                            drow[f_best] = value;
                        }

                        var worst = drow[f_worst];

                        if (worst == undefined || worst < value) {
                            drow[f_worst] = value;
                        }

                        drow[f_sum] += value;
                        var sum = drow[f_sum];
                        drow[f_cnt]++;
                        var cnt = drow[f_cnt];
                        var sqsum = drow[f_sqsum] + value * value;
                        drow[f_sqsum] = sqsum;
                        drow[f_avg] = drow[f_sum] / drow[f_cnt];
                        drow[f_stdev] = Math.sqrt((cnt * sqsum - sum * sum) / (cnt * (cnt - 1)));
                    }

                    drow[f_loss] = ((drow[f_snt] - drow[f_cnt]) / drow[f_snt]) * 100;
                }

                tableModel.setData(data);

                if (retval['again']) {
                    var next_round = function() {
                        tr.Server.getInstance().callAsync(function(ret, exc, id) {
                            that.__fill_table(ret, exc, id);
                        }, 'run_tr', {
                            handle : retval['handle'],
                            point  : retval['point']
                        });
                    };

                    qx.event.Timer.once(next_round, this, sleep * 1000);
                }
                else {
                    this.__stop_table();
                }
            }
            else {
                this.__stop_table();
            }
        },


        /**
         * TODOC
         *
         * @type member
         * @param data {var} TODOC
         * @param exc {Exception} TODOC
         * @param id {var} TODOC
         * @return {void} 
         */
        __stop_handler : function(data, exc, id) {
            if (exc == null) {
                qx.event.message.Bus.dispatch('tr.status', 'stopped');
            } else {
                this.error(exc);
            }
        },

        subscribe: function(handle){
            qx.event.message.Bus.subscribe(handle+'::data', this.__handle_tr, this);
        },


        /**
         * TODOC
         *
         * @type member
         * @param m {var} TODOC
         * @return {void} 
         */
        __handle_tr : function(m) {
            var that = this;
            var cmd = m.getData();

            switch(cmd['action'])
            {
                case 'stop':
                    qx.event.message.Bus.dispatch('tr.status', 'stopping');
                    tr.Server.getInstance().callAsync(function(ret, exc, id) {
                        that.__stop_handler(ret, exc, id);
                    }, 'stop_tr', this.__handle);

                    break;

                case 'go':
                    this.__data = [];
                    this.__tableModel.setData(this.__data);
                    this.__delay = cmd['delay'];

                    for (var i=0; i<10; i++) {
                        this.__tableModel.setColumnSortable(i, false);
                    }

                    qx.event.message.Bus.dispatch('tr.status', 'starting');
                    tr.Server.getInstance().callAsync(function(ret, exc, id) {
                        that.__fill_table(ret, exc, id);
                    }, 'run_tr', {
                        host   : cmd['host'],
                        rounds : cmd['rounds'],
                        delay  : cmd['delay']
                    });

                    break;

                default:
                    this.error('Unknown Command ' + cmd['action']);
            }
        }
    }
});

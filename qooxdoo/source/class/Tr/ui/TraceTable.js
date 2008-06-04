/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * a widget showing the Tr target tree
 */

qx.Class.define('Tr.ui.TraceTable', 
{
    extend: qx.ui.table.Table,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */


    construct: function () {
       
        var tableModel = new qx.ui.table.model.Simple();
        this.__tableModel = tableModel;
        tableModel.setColumns([ this.tr("Hop"), this.tr("Host"),this.tr("Ip"), 
                                this.tr("Loss [%]"), this.tr("Sent"), this.tr("Last [ms]"), //"; help syntax highliter
                                this.tr("Avg [ms]"), this.tr("Best [ms]"), this.tr("Worst [ms]"), this.tr("StDev [ms]") ]);
        var custom = {
            tableColumnModel:  function(obj) {
                return new qx.ui.table.columnmodel.Resize(obj);
            }
        };
        with(this){
			base(arguments,tableModel,custom);
            set({
                width: '100%',
                height: '1*',
                border: 'dark-shadow',
                showCellFocusIndicator: false,
                statusBarVisible: false
			});
        };
      	var tcm = this.getTableColumnModel();
        this.__tcm = tcm;

        //tcm.setDataCellRenderer(0, new Tr.ui.Cellrenderer(2));
        tcm.setDataCellRenderer(3, new Tr.ui.Cellrenderer(0,' %'));
        tcm.setDataCellRenderer(4, new Tr.ui.Cellrenderer(0));
        
        var render_ms = new Tr.ui.Cellrenderer(1);

        for (var i=5;i<10;i++){
            tcm.setDataCellRenderer(i, render_ms);
        }
        

        // Obtain the behavior object to manipulate
        var resizeBehavior = tcm.getBehavior();
        // This uses the set() method to set all attriutes at once; uses flex
        resizeBehavior.set(0, { width:"2*"});
        resizeBehavior.set(1, { width:"9*"});
        resizeBehavior.set(2, { width:"5*"});

        for (var i=3;i<10;i++){
            resizeBehavior.set(i, { width:"3*"});
        }
        qx.event.message.Bus.subscribe('tr.cmd',this.__handle_tr,this);
    },

    /*
    *****************************************************************************
     Statics
    *****************************************************************************
    */
	members: {
        __make_empty_row: function (){            
            return ([undefined,undefined,undefined,0,0,undefined,undefined,undefined,undefined,undefined,0,0,0]);
        },
        __handle_tr: function(m){
            var self = this;
            var f_hop = 0,f_host=1,f_ip=2,f_loss=3,f_snt=4,f_last=5,f_avg=6,f_best=7,f_worst=8,f_stdev=9,f_cnt=10,f_sum=11,f_sqsum=12;
            var fill_table;
            fill_table = function(retval,exc,id){
                if (exc == null){ 
                    if ( self.__handle == undefined ) {
                        qx.event.message.Bus.dispatch('tr.status','started');
                    }
                    self.__handle = retval['handle'];
                    var tableModel = self.__tableModel;
                    var lines = retval['output'].length;
                    var data = self.__data;
                    for(var i=0;i<lines;i++){
                        var hop = retval['output'][i][0];
                        var host = retval['output'][i][1];
                        var ip = retval['output'][i][2];
                        var value = retval['output'][i][3];
                        var ii = 0;
                        var max = data.length;
                        while ( ii < max 
                                && ( Math.floor(data[ii][0]) < hop 
                                     || ( Math.floor(data[ii][0]) == hop && data[ii][1] != host)
                                   )
                               ){
                            ii++;
                        }
                        if (ii == max || ( Math.floor(data[ii][0]) == hop && data[ii][1] != host) ){
                            if (ii < max){
                                hop = data[ii][0] + 0.1;                                
                            }
                            data.splice(ii,0,self.__make_empty_row());
                            data[ii][0] = hop;
                        }

                        var drow = data[ii];
                        if (drow[f_host] == undefined){
                            drow[f_host] = host;
                        }
                        if (drow[f_ip] == undefined){
                            drow[f_ip] = ip;
                        }
                        drow[f_snt]++;
                        drow[f_last] = value;
                        var best = drow[f_best];
                        if (best == undefined || best > value){
                            drow[f_best] = value;     
                        }
                        var worst = drow[f_worst]; 
                        if (worst == undefined || worst < value){
                            drow[f_worst] = value;     
                        }
                                

                        if (value != undefined){
                            drow[f_sum] += value;                            
                            var sum = drow[f_sum];
                            drow[f_cnt] ++;
                            var cnt = drow[f_cnt];
                            var sqsum =  drow[f_sqsum]+value*value;
                            drow[f_sqsum] = sqsum;    
                            drow[f_avg] = drow[f_sum]/drow[f_cnt];
                            drow[f_stdev] = Math.sqrt((cnt*sqsum-sum*sum)/(cnt*(cnt-1)))
                        }
                        drow[f_loss] = ((drow[f_snt]-drow[f_cnt])/drow[f_snt])*100;
                    } 

                    tableModel.setData(data);
                    if (retval['again']){
                        var next_round = function (){Tr.Server.getInstance().callAsync(
                                                     fill_table,'run_tr',{ handle: retval['handle'],
                                                                            point:  retval['point']})};
                        qx.client.Timer.once(next_round,self,0);
                    } else
                    {
                        for (var i=0;i<10;i++){
                            tableModel.setColumnSortable(i,true);
                        }
                        qx.event.message.Bus.dispatch('tr.status','stopped');
                        self.__handle = undefined;
                    }
                }
                else {
                    alert(exc);   
                    if (self.__handle){                     
                        self.__handle = undefined;
                    }
                    for (var i=0;i<10;i++){
                        self.__tableModel.setColumnSortable(i,true);
                    }
                    qx.event.message.Bus.dispatch('tr.status','stopped');
                }				
            };

            var handle_returns = function (data,exc,id){
                if (exc != null){
                   alert(exc);
                }               
            };

            var cmd = m.getData();
            switch(cmd['action']){
            case 'stop':
                qx.event.message.Bus.dispatch('tr.status','stopping');
                Tr.Server.getInstance().callAsync(handle_returns,'stop_tr',this.__handle);
                break;
            case 'go':
                this.__data = [];
                this.__tableModel.setData(this.__data);
                this.__delay = cmd['delay'];
                for (var i=0;i<10;i++){
                    this.__tableModel.setColumnSortable(i,false);
                }                
                qx.event.message.Bus.dispatch('tr.status','starting');
                Tr.Server.getInstance().callAsync(fill_table,'run_tr',{host: cmd['host'], rounds: cmd['rounds'], delay: cmd['delay']});
                break;
            default:
                alert('Unknown Command '+cmd['action']);
            }
        }
	}
});
 
 

/* ************************************************************************
#module(Mtr)
************************************************************************ */

/**
 * a widget showing the Mtr target tree
 */

qx.Class.define('Mtr.ui.TraceTable', 
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
                                this.tr("Loss [%]"), this.tr("Sent [ms]"), this.tr("Last [ms]"), //"; help syntax highliter
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

        tcm.setDataCellRenderer(3, new Mtr.ui.Cellrenderer(0,' %'));
        tcm.setDataCellRenderer(4, new Mtr.ui.Cellrenderer(0));
        
        var render_ms = new Mtr.ui.Cellrenderer(1);

        for (var i=5;i<10;i++){
            tcm.setDataCellRenderer(i, render_ms);
        }
        

        // Obtain the behavior object to manipulate
        var resizeBehavior = tcm.getBehavior();
        // This uses the set() method to set all attriutes at once; uses flex
        resizeBehavior.set(0, { width:"1*", minWidth:20, maxWidth:30  });
        resizeBehavior.set(1, { width:"10*", minWidth:80, maxWidth:300 });
        resizeBehavior.set(2, { width:"6*", minWidth:60, maxWidth:200 });

        for (var i=3;i<10;i++){
            resizeBehavior.set(i, { width:"2*", minWidth:40, maxWidth:100 });
        }
        qx.event.message.Bus.subscribe('mtr.cmd',this.__handle_mtr,this);
    },

    /*
    *****************************************************************************
     Statics
    *****************************************************************************
    */
	members: {
        __make_empty_row: function (){            
            return ([undefined,'waiting for name','waiting for ip',0,0,undefined,undefined,undefined,undefined,undefined,0,0,0]);
        },
        __handle_mtr: function(m){
            var self = this;
            var f_hop = 0,f_host=1,f_ip=2,f_loss=3,f_snt=4,f_last=5,f_avg=6,f_best=7,f_worst=8,f_stdev=9,f_cnt=10,f_sum=11,f_sqsum=12;
            var fill_table;
            fill_table = function(retval,exc,id){
                if (exc == null){ 
                    if ( self.__handle == undefined ) {
                        qx.event.message.Bus.dispatch('mtr.status','started');
                    }
                    self.__handle = retval['handle'];
                    var tableModel = self.__tableModel;
                    var rowcount = tableModel.getRowCount();
                    var lines = retval['output'].length;
                    var data = self.__data;
                    for(var i=0;i<lines;i++){
                        var cmd = retval['output'][i][0];
                        var row = retval['output'][i][1];
                        var value = retval['output'][i][2];
                       if (rowcount <= row){
                            for (var ii=rowcount;rowcount <= row;rowcount++){
                                data.push(self.__make_empty_row());
                            };
                        }; 
                        var drow = data[row];
                        drow[f_hop] = row+1;
                        switch(cmd){
                        case 'h':
                            drow[f_ip] = value;
                            break;
                        case 'd':
                            drow[f_host] = value;
                            break; 
                        case 'p':
                            var snt = data[0][f_snt];
                            if (row == 0) {
                                snt++;
                                for (ii=0;ii<rowcount;ii++){                                    
                                    if (retval['again'] && snt > data[ii][f_cnt]){
                                        data[ii][f_snt] = snt-1;
                                    } else {
                                        data[ii][f_snt] = snt;
                                    }
                                    data[ii][f_loss]=(1-data[ii][f_cnt]/data[ii][f_snt])*100;
                                }
                            }                            
                            value = value/1000.0;
                            drow[f_last] = value;

                            var best = drow[f_best];
                            if (best == undefined || best > value){
                                drow[f_best] = value;     
                            }

                            var worst = drow[f_worst]; 
                            if (worst == undefined || worst < value){
                                drow[f_worst] = value;     
                            }
                                
                            var cnt =  drow[f_cnt]+1;

                            if (cnt > drow[f_snt]){
                                drow[f_snt] = cnt;
                            }

                            drow[f_cnt] = cnt;

                            drow[f_loss] = (1-cnt/drow[f_snt])*100;

                            var sum =  drow[f_sum]+value;
                            drow[f_sum] = sum;    
                            var sqsum =  drow[f_sqsum]+value*value;
                            drow[f_sqsum] = sqsum;    

                            drow[f_avg] = sum/cnt;
                            drow[f_stdev] = Math.sqrt((cnt*sqsum-sum*sum)/(cnt*(cnt-1)))
                            break;

                        default:
                            self.debug(row);
                            break;
                        }
                    } 

                    tableModel.setData(data);
                    if (retval['again']){
                        var next_round = function (){Mtr.Server.getInstance().callAsync(
                                                     fill_table,'run_mtr',{ handle: retval['handle'],
                                                                            point:  retval['point']})};
                        qx.client.Timer.once(next_round,self,0);
                    } else
                    {
                        for (var i=0;i<10;i++){
                            tableModel.setColumnSortable(i,true);
                        }
                        qx.event.message.Bus.dispatch('mtr.status','stopped');
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
                    qx.event.message.Bus.dispatch('mtr.status','stopped');
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
                qx.event.message.Bus.dispatch('mtr.status','stopping');
                Mtr.Server.getInstance().callAsync(handle_returns,'stop_mtr',this.__handle);
                break;
            case 'go':
                this.__data = [this.__make_empty_row()];
                this.__tableModel.setData(this.__data);
                this.__delay = cmd['delay'];
                for (var i=0;i<10;i++){
                    this.__tableModel.setColumnSortable(i,false);
                }                
                qx.event.message.Bus.dispatch('mtr.status','starting');
                Mtr.Server.getInstance().callAsync(fill_table,'run_mtr',{host: cmd['host'], rounds: cmd['rounds'], delay: cmd['delay']});
                break;
            default:
                alert('Unknown Command '+cmd['action']);
            }
        }
	}
});
 
 

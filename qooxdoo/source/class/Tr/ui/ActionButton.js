/* ************************************************************************
#module(Tr)
************************************************************************ */

/**
 * a widget showing the Tr graph overview
 */

qx.Class.define('Tr.ui.ActionButton', 
{
    extend: qx.ui.layout.VerticalBoxLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    construct: function () {
        this.base(arguments);

        this.set({
            height: 'auto',
            width: 'auto',
            horizontalChildrenAlign: 'left'
        });
        var hbox = new  qx.ui.layout.HorizontalBoxLayout;
        hbox.set({
            height: 'auto',
            width: 'auto',
            verticalChildrenAlign: 'middle'
        });
        var lab1 = new qx.ui.basic.Label(this.tr("Host"));
        lab1.set({
            paddingRight: 6
        });
        hbox.add(lab1);
        var host = new qx.ui.form.TextField();
        host.set({
            width: 200,
            height: 'auto',
            border: 'dark-shadow',
            padding: 1
        });
        hbox.add(host);
        this.__host = host;
        var lab2 = new qx.ui.basic.Label(this.tr("Delay"));
        lab2.set({
            paddingRight: 6,
            paddingLeft: 12
        });
        hbox.add(lab2);
        var delay = new qx.ui.form.Spinner(1,2,60);
        delay.set({
            border: 'dark-shadow',
            width: 45
        });
        hbox.add(delay);
        this.__delay = delay;

        var lab3 = new qx.ui.basic.Label(this.tr("Rounds"));
        lab3.set({
            paddingRight: 6,
            paddingLeft: 12
        });
        hbox.add(lab3);
        var rounds = new qx.ui.form.Spinner(1,20,200);
        rounds.set({
            border: 'dark-shadow',
            width: 45
        });
        hbox.add(rounds);
        this.__rounds = rounds;

        var button = new qx.ui.form.Button('');
        this.__button = button;
		button.set({
            marginLeft: 10,
            width: 60,
            height: 'auto',
            border: 'dark-shadow',
            padding: 2
        });
        hbox.add(button);
        this.add(hbox);
        var info = new qx.ui.basic.Atom();
        info.set({
            marginTop: 3,
            padding: 3,
            textColor: 'red',
            width: '100%',
            height: 'auto',
            backgroundColor: '#f0f0f0',
            visibility: false
        });        
   		qx.event.message.Bus.subscribe('tr.info',this.__set_info,this);
        this.add(info);
        this.__info = info;

   		qx.event.message.Bus.subscribe('tr.status',this.__set_status,this);
        qx.event.message.Bus.dispatch('tr.status','stopped');
    
        var start_trace = function(event) {            
            qx.event.message.Bus.dispatch('tr.cmd',{
                    action: button.getUserData('action'),
                    host:   host.getValue(),
                    delay:  delay.getValue(),
                    rounds: rounds.getValue()
            });
        };                    

//      var self=this;
//      host.addEventListener('keyup',function(e){if(e.getKeyIdentifier() == 'Enter'){start_trace()}});
        host.addEventListener('execute',start_trace);
        button.addEventListener('execute', start_trace );

        var history = qx.client.History.getInstance();
        var history_action = function(event){
            var targ = event.getData();
            host.setValue(targ);
            history.addToHistory(targ,'SmokeTraceroute to '+targ);
            start_trace();           
        }
        history.addEventListener('request', history_action);

        // if we got called with a host on the commandline
        var initial_host = qx.client.History.getInstance().getState();
        if (initial_host){
            host.setValue(initial_host);
            history.addToHistory(initial_host,'SmokeTraceroute to '+initial_host);        
            // dispatch this task once all the initializations are done
            qx.client.Timer.once(start_trace,this,0);
        }        
    },

	members: {
        __set_info: function(e){
            this.__info.set({
                label: e.getData(),
                visibility: true
            });
        },
		__set_status: function(m){
            var host = this.__host;
            var rounds = this.__rounds;
            var delay = this.__delay;
            with(this.__button){
                // this.debug(m.getData());
                switch(m.getData()){
                case 'starting':
                    if (getUserData('action') == 'go') {
                        setLabel(this.tr("Starting"));
                        this.__info.setVisibility(false);
                        border: 'dark-shadow'          
        	    		setEnabled(false);
                        host.setEnabled(false);
                        rounds.setEnabled(false);
                        delay.setEnabled(false);
                    }
                    break;
                case 'stopping':
                    if (getUserData('action') == 'stop') {
                        setLabel(this.tr("Stopping"));
        	    		setEnabled(false);
                        host.setEnabled(false);
                        rounds.setEnabled(false);
                        delay.setEnabled(false);
                    }
                    break;
                case 'stopped':
                    setUserData('action','go');
                    setLabel(this.tr("Go"));
    			    setEnabled(true);                
                    host.setEnabled(true);
                    rounds.setEnabled(true);
                    delay.setEnabled(true);
                    break;
                case 'started':
                    setUserData('action','stop');
                    setLabel(this.tr("Stop"));
    			    setEnabled(true);                
                    host.setEnabled(false);
                    rounds.setEnabled(false);
                    delay.setEnabled(false);
                    break;
                default:
                    alert('Unknown Status Message: '+m.getData());
                }
            }
		}
	}
	

});
 
 

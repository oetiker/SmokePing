/* ************************************************************************
#module(Mtr)
************************************************************************ */

/**
 * a widget showing the Mtr graph overview
 */

qx.Class.define('Mtr.ui.ActionButton', 
{
    extend: qx.ui.layout.HorizontalBoxLayout,        

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
            verticalChildrenAlign: 'middle'
        });
        var lab1 = new qx.ui.basic.Label(this.tr("Host"));
        lab1.set({
            paddingRight: 6
        });
        this.add(lab1);
        var host = new qx.ui.form.TextField();
        host.set({
            width: 200,
            height: 'auto',
            border: 'dark-shadow',
            padding: 1
        });
        this.add(host);
        this.__host = host;

        var lab2 = new qx.ui.basic.Label(this.tr("Delay"));
        lab2.set({
            paddingRight: 6,
            paddingLeft: 12
        });
        this.add(lab2);
        var delay = new qx.ui.form.Spinner(1,5,60);
        delay.set({
            border: 'dark-shadow'
        });
        this.add(delay);
        this.__delay = delay;

        var lab3 = new qx.ui.basic.Label(this.tr("Rounds"));
        lab3.set({
            paddingRight: 6,
            paddingLeft: 12
        });
        this.add(lab3);
        var rounds = new qx.ui.form.Spinner(1,20,200);
        rounds.set({
            border: 'dark-shadow'
        });
        this.add(rounds);
        this.__rounds = rounds;

        var button = new qx.ui.form.Button('');
        this.__button = button;
		button.set({
            marginLeft: 10,
            width: 50,
            height: 'auto',
            border: 'dark-shadow',
            padding: 2
        });
        this.add(button);

   		qx.event.message.Bus.subscribe('mtr.status',this.__set_status,this);
        qx.event.message.Bus.dispatch('mtr.status','stopped');
    
        var start_trace = function(event) {            
            qx.event.message.Bus.dispatch('mtr.cmd',{
                    action: button.getUserData('action'),
                    host:   host.getValue(),
                    delay:  delay.getValue(),
                    rounds: rounds.getValue()
            });
        };                    

        button.addEventListener('execute', start_trace );

        var history_action = function(event){
            host.setValue(event.getData());            
            start_trace();           
        }
        qx.client.History.getInstance().addEventListener('request', history_action);

        // if we got called with a host on the commandline
        var initial_host = qx.client.History.getInstance().getState();
        if (initial_host){
            host.setValue(initial_host);
            // dispatch this task once all the initializations are done
            qx.client.Timer.once(start_trace,this,0);
        }        
    },

	members: {
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
 
 

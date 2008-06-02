/* ************************************************************************

#module(Mtr)
#resource(Mtr.image:image)
#embed(Mtr.image/*)

************************************************************************ */

qx.Class.define('Mtr.Application', 
{
    extend: qx.application.Gui,
       
    members: 
    {           
        main: function()
        {
            var self=this;
            this.base(arguments);

	        qx.io.Alias.getInstance().add(
    	       'MT', qx.core.Setting.get('Mtr.resourceUri')
        	);

  			// if we run with a file:// url make sure 
			// the app finds the Mtr service (Mtr.cgi)

            Mtr.Server.getInstance().setLocalUrl(
			    'http://johan.oetiker.ch/~oetiker/mtr/'
            );

            var base_layout = new qx.ui.layout.VerticalBoxLayout();
            with(base_layout){
                setPadding(8);
                setLocation(0,0);
                setWidth('100%');
                setHeight('100%');
                setSpacing(10);
                setBackgroundColor('white');
            };            
            base_layout.addToDocument();
            var top = new qx.ui.layout.HorizontalBoxLayout();
            top.set({
                height: 'auto'
            });
			var title = new qx.ui.basic.Atom(this.tr("MTR AJAX Frontend"));
			with(title){
            	setTextColor('#b0b0b0');
            	setFont(qx.ui.core.Font.fromString('20px bold sans-serif'));
			}
			top.add(title);
            top.add(new qx.ui.basic.HorizontalSpacer());
            top.add(new Mtr.ui.ActionButton());
            base_layout.add(top);
			var trace = new Mtr.ui.TraceTable();
            base_layout.add(trace);
        },
        
        close : function(e)
        {
            this.base(arguments);
            // return "Mtr Web UI: "
            //      + "Do you really want to close the application?";
        },
        
			
		terminate : function(e) {
			this.base(arguments);
		}

        /********************************************************************
         * Functional Block Methods
         ********************************************************************/

    },
		



    /*
    *****************************************************************************
    SETTINGS
    *****************************************************************************
    */

    settings : {
			'Mtr.resourceUri' : './resource'
	}
});
 

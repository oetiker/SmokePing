/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping graph overview
 */

qx.Class.define('Smokeping.ui.Graphs', 
{
    extend: qx.ui.layout.FlowLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param base_url   {String}   Path to the location of the image generator
     *
     */

    construct: function (url) {

        with(this){
			base(arguments,'root node');
            setOverflow('scrollY');
            setBackgroundColor('white');
            setBorder('inset');
            setWidth('100%');
            setHeight('100%');
            setVerticalSpacing(10);
            setHorizontalSpacing(10);
			setPadding(10);
        };
		var load_graphs = function(m){
			var files = m.getData()
			this.removeAll();
			for(var i=0;i<files.length;i++){
   			   	var button = new qx.ui.form.Button(null,qx.io.Alias.getInstance().resolve('SP/image/ajax-loader.gif'));
				this.add(button);
				button.addEventListener('execute',function(e){					
					this.setEnabled(false);
					var window = this.getUserData('window');					
					window.positionRelativeTo(this.getElement(),2,-4);
					window.open();
				},button);

				var preloader = qx.io.image.PreloaderManager.getInstance().create(url + 'grapher.cgi?g=' + files[i]);
				preloader.setUserData('button',button); // it seems javascript does not do closures
				preloader.addEventListener('load', function(e) {					
					var button = this.getUserData('button');	/// so we use this to whisk the image into the event			
					var image = button.getIconObject();
					image.setSource(this.getSource());
					qx.io.image.PreloaderManager.getInstance().remove(this);

					var window = new Smokeping.ui.Navigator(image);
					window.addToDocument();
					window.addEventListener('beforeDisappear',function (e){
						this.setEnabled(true);
					},button);
					button.setUserData('window',window);

					// image.setWidth(preloader.getWidth()-10);
		    		//if (image.isLoaded()) {
					//	this.debug('outer '+image.getOuterHeight());
					//	this.debug('inner '+image.getInnerHeight());
					//	this.debug('box '+image.getBoxHeight());
				    //	this.debug('prefinner '+image.getPreferredInnerHeight());
					//	this.debug('prefbox '+image.getPreferredBoxHeight());
				},preloader);
			}
		};
                    
		qx.event.message.Bus.subscribe('sp.menu.folder',load_graphs,this);
    }


});
 
 

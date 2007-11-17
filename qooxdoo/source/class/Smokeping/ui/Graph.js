/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * a widget showing the smokeping graph overview
 */

var default_width = null;
var default_height = null;

qx.Class.define('Smokeping.ui.Graph', 
{
    extend: qx.ui.layout.BoxLayout,        

    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param base_url   {String}   Path to the location of the image generator
     *
     */

    construct: function (src) {
        with(this){
			base(arguments);
			if (default_width){
				setWidth(default_width)
			} 
			else {
	            setWidth('auto');
			}
			if (default_height){
				setHeight(default_height);
			}
			else {
				setHeight('auto');
			};
			setBorder(new qx.ui.core.Border(1));
		    setHorizontalChildrenAlign('center');
	        setVerticalChildrenAlign('middle');
			_highlight();
			var loader = new qx.ui.basic.Image(qx.io.Alias.getInstance().resolve('SP/image/ajax-loader.gif'));	
    	    add(loader);
			_preloader = qx.io.image.PreloaderManager.getInstance().create(src);
			if (_preloader.isLoaded()){
				qx.client.Timer.once(_image_loader,this,0);
			} else {
				_preloader.addEventListener('load', _image_loader, this);
			}
			addEventListener('mouseover',_highlight,this);
			addEventListener('mouseout',_unhighlight,this);
		}
	},

	members: {
		_image_loader: function(e) {					
			with(this){
				default_width = _preloader.getWidth();
				default_height = _preloader.getHeight();
				_image = new qx.ui.basic.Image(_preloader.getSource());
				_unhighlight();
				removeAll()
				add(_image);
				addEventListener('click',_open_navigator,this);
			}
		},
		_open_navigator: function(e){
			with(this){
				setEnabled(false);
				_unhighlight();
				_window = new Smokeping.ui.Navigator(_image);
				_window.addToDocument();
				_window.positionRelativeTo(getElement(),2,-4);
				addEventListener('beforeDisappear',_kill_window,this);
				_window.open();
				_window.addEventListener('beforeDisappear',_close_window,this);
			}
		},
		_close_window: function(e){
			this.setEnabled(true);
		},
		_kill_window: function(e){
			with(this){
				_window.close();
				_window.dispose();
			}
		},
		_highlight: function(e){
			this.setBackgroundColor('#f8f8f8');
			with(this.getBorder()){
				setStyle('dotted');
				setColor('#808080');
			}
		},
		_unhighlight: function(e){
			this.setBackgroundColor('transparent');
			with(this.getBorder()){
				setStyle('solid');
				setColor('transparent');
			}			
		},
	}
	

});
 
 

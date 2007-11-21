/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * Lets you selcet an Area. Depending on the angel of your selection you get
 * a time, a range or both.
 *
 */

qx.Class.define('Smokeping.ui.Zoomer',
{
    extend: qx.ui.layout.CanvasLayout,        

	include: Smokeping.ui.MPosition,
    /*
    *****************************************************************************
       CONSTRUCTOR
    *****************************************************************************
    */

    /**
     * @param target  {Widget}    What surface should we base our selection on
     *
     * @param width   {Integer}   Width of the 'interesting' area of the target
     *
     * @param height  {Integer}   Height ot the 'interesting' area of the target
     *
     * @param right   {Integer}   Distance from the right edge
     *
     * @param top     {Integer}   Distance from the top
     *
	 * The zoomer will not activate if the ctrl key is pressed. This allows
     * for the Mover to act on these events
     *
     */

    construct: function (target,width,height,top,right) {
        this._target = target;
		this._width = width;
		this._height = height+1; // some where the calc is 1 off. this fixes it
		this._top = top;
		this._right = right;
		with(this){
			base(arguments);
			set({
				width:		  '100%',
				height:		  '100%',
                visibility:   false
			});
		}
        var zoomer_defaults = {
            backgroundColor: 'black',
            opacity: 0.1,
            overflow: 'hidden' // important to make box go to 'zero height' on ie6
        };
	    var dir = ['left','right','top','bottom' ];
        var z = [];
        this._zoomer = z;
	    for(var i=0;i<dir.length;i++){
			z[dir[i]] = new qx.ui.basic.Terminator();    
	        z[dir[i]].set(zoomer_defaults);
	        this.add(z[dir[i]]);
		}
        
        z['frame'] = new qx.ui.basic.Terminator();    
        z['frame'].set(zoomer_defaults);
        z['frame'].set({
			opacity: 1,
            backgroundColor: 'transparent',
            border: new qx.ui.core.Border(1,'dotted','#808080')			
        });
        
		this.add(z['frame']);
		this._zooming = false; // we are not curently in zoom mode
  		this._target.addEventListener("mousedown", this._zoom_start,this);
        this._target.addEventListener("mousemove", this._zoom_move,this);
        this._target.addEventListener("mouseup",   this._zoom_end,this);
    },

	members: {
    	_zoom_start: function(e){
			if (e.isCtrlPressed()) return;
			this._zooming = true;
			var z = this._zoomer;
			this._init_cache();	

            this._selector_start_x = this._get_mouse_x(e); 
            this._selector_start_y = this._get_mouse_y(e);
 
            this._target.setCapture(true);                                    
            this._zoom_move(e);
            this.setVisibility(true);
    	},

		_zoom_move: function(e){
			var z = this._zoomer;
            if (this._target.getCapture() && this._zooming ){        

       			var mouse_x = this._get_mouse_x(e);

                var mouse_left_x;
                var mouse_right_x;
	            if (mouse_x > this._selector_start_x){
                    mouse_left_x = this._selector_start_x;
                    mouse_right_x = mouse_x;
                }
                else {
                    mouse_right_x = this._selector_start_x;
                    mouse_left_x = mouse_x;
                }        

       			var mouse_y = this._get_mouse_y(e);
                var mouse_top_y;
                var mouse_bottom_y;
	            if (mouse_y > this._selector_start_y){
                    mouse_top_y = this._selector_start_y;
                    mouse_bottom_y = mouse_y;
                }
                else {
                    mouse_bottom_y = this._selector_start_y;
                    mouse_top_y = mouse_y;
                }        

                var time_sel = 1;
                var range_sel = 1;
                var pi = 3.14159265;
                var angle = Math.atan ((mouse_right_x - mouse_left_x) / (mouse_bottom_y - mouse_top_y));
                if ( angle > Math.PI/2 * 0.85){
                    range_sel = 0;
                }
                if ( angle < Math.PI/2 * 0.15){
                    time_sel = 0;
                }
                
                z['top'].set({
	    			left: time_sel ? mouse_left_x : this._canvas_left,
		            width: time_sel ? mouse_right_x - mouse_left_x : this._width,
                    top: 0,
                    height: range_sel ? mouse_top_y : this._canvas_top
    			});
                           
                z['bottom'].set({
	    			left: time_sel ? mouse_left_x : this._canvas_left,
		            width: time_sel ? mouse_right_x - mouse_left_x : this._width,
                    top: range_sel ? mouse_bottom_y : this._canvas_top + this._height,
                    height: range_sel ? this._image_height - mouse_bottom_y : this._canvas_bottom
		    	});

    			z['left'].set({
		            width: time_sel ? mouse_left_x: this._canvas_left,
                    height: this._image_height
                });

                z['right'].set({
	    			left: time_sel ? mouse_right_x : this._image_width - this._canvas_right,
		            width: time_sel ? this._image_width - mouse_right_x :  this._canvas_right,
                    height: this._image_height
    			});
                z['frame'].set({
		    		left: time_sel ? mouse_left_x : this._canvas_left,        
			        width: time_sel ? mouse_right_x - mouse_left_x : this._width,
                    top: range_sel ? mouse_top_y : this._canvas_top,
                    height: range_sel ? mouse_bottom_y - mouse_top_y : this._height
    			});			
			}
		},
		_zoom_end: function(e){
			if (!this._zooming) return;
			var z = this._zoomer;
			this._target.setCapture(false);
            this.setVisibility(false);
			this._zooming = false;

            if (z['bottom'].getTop() == z['top'].getTop()+z['top'].getHeight()){
                this._zoom_factor_top = 0;
                this._zoom_factor_bottom = 0;
            }
            else {
                var prev_factor = 1 - this._zoom_factor_top - this._zoom_factor_bottom; 
                this._zoom_factor_top = 
					(z['top'].getHeight()-this._canvas_top)/this._height * prev_factor
                        + this._zoom_factor_top;
                this.zoom_factor_bottom =
                    (z['bottom'].getHeight()-this._canvas_bottom)/this._height * prev_factor
                        + this._zoom_factor_bottom;
             }
		}
	}


});
 
 

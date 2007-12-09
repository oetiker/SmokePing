/* ************************************************************************
#module(Smokeping)
************************************************************************ */

/**
 * some mouse handling routines for thegraph mover and zoomer.
 */

qx.Mixin.define('Smokeping.ui.MPosition',
{

	members: {
		_init_cache: function(){
	        var el = this._target.getElement();
	        this._page_left = qx.html.Location.getPageAreaLeft(el);
	        this._page_top = qx.html.Location.getPageAreaTop(el);
			this._image_width = qx.html.Location.getPageAreaRight(el) - this._page_left;
	        this._image_height = qx.html.Location.getPageAreaBottom(el) - this._page_top ;
            this._canvas_top = this._top;
	        this._canvas_left = this._image_width-this._width-this._right;
	        this._canvas_right = this._right;
            this._canvas_bottom = this._image_height-this._height-this._top;
		},

        _get_mouse_y: function(e){
	            var mouse_y = e.getPageY()-this._page_top;
	
    	        if (mouse_y < this._canvas_top) {
        	        mouse_y = this._canvas_top;
            	} 
                if (mouse_y > this._canvas_top + this._height) {
                	mouse_y = this._canvas_top + this._height;
	            }
                return mouse_y;
        },

        _get_mouse_x: function(e){
	            var mouse_x = e.getPageX()-this._page_left;
	
    	        if (mouse_x < this._canvas_left) {
        	        mouse_x = this._canvas_left;
            	} 
                if (mouse_x > this._canvas_left + this._width) {
                	mouse_x = this._canvas_left + this._width;
	            }
                return mouse_x;
        }
	}


});
 
 

/**
 * Interface Elements for jQuery
 * Selectables
 *
 * http://interface.eyecon.ro
 *
 * Copyright (c) 2006 Stefan Petre
 * Dual licensed under the MIT (MIT-LICENSE.txt)
 * and GPL (GPL-LICENSE.txt) licenses.
 *
 * Modified for smokeping ... we hacked in the call
 * we need after the area is selected. Yes there is
 * certainly a much better way todo this! Let us know!
 *
 */

jQuery.selectHelper = null;
jQuery.selectKeyHelper = false;
jQuery.selectdrug = null;
jQuery.selectCurrent = [];	// For current selection
jQuery.selectKeyDown = function(e) {
	var pressedKey = e.charCode || e.keyCode || -1;
	if (pressedKey == 17 || pressedKey == 16) {
		jQuery.selectKeyHelper = true;
	}
};
jQuery.selectKeyUp = function(e) {
	jQuery.selectKeyHelper = false;
};
jQuery.selectstart = function(e) {
	this.f.pointer = jQuery.iUtil.getPointer(e);
	this.f.pos = jQuery.extend(
		jQuery.iUtil.getPosition(this), 
		jQuery.iUtil.getSize(this)
	);
	
	this.f.scr = jQuery.iUtil.getScroll(this);
	this.f.pointer.x -= this.f.pos.x;
	this.f.pointer.y -= this.f.pos.y;
	jQuery(this).append(jQuery.selectHelper.get(0));
	if (this.f.hc)
		jQuery.selectHelper.addClass(this.f.hc).css('display','block');
	jQuery.selectHelper.css(
		{
			display: 'block',
			width: '0px',
			height: '0px'
		}
	);
	if (this.f.o) {
		jQuery.selectHelper.css('opacity', this.f.o);
	}

	jQuery.selectdrug = this;
	jQuery.selectedone = false;
	jQuery.selectCurrent = [];	// For current selection state
	this.f.el.each(
		function ()
		{
			this.pos = {
				x: this.offsetLeft + (this.currentStyle && !jQuery.browser.opera ?parseInt(this.currentStyle.borderLeftWidth)||0:0) + (jQuery.selectdrug.scrollLeft||0), 
				y: this.offsetTop + (this.currentStyle && !jQuery.browser.opera ?parseInt(this.currentStyle.borderTopWidth)||0:0) + (jQuery.selectdrug.scrollTop||0),
				wb: this.offsetWidth,
				hb: this.offsetHeight
			};
			if (this.s == true) {
				if (jQuery.selectKeyHelper == false) {
					this.s = false;
					jQuery(this).removeClass(jQuery.selectdrug.f.sc);
				} else {
					jQuery.selectedone = true;

					// Save current state
					jQuery.selectCurrent[jQuery.selectCurrent.length] = jQuery.attr(this,'id');
				}
			}
		}
	);
	jQuery.selectcheck.apply(this, [e]);
	jQuery(document)
		.bind('mousemove', jQuery.selectcheck)
		.bind('mouseup', jQuery.selectstop);
	return false;
};
jQuery.selectcheck = function(e)
{
	if(!jQuery.selectdrug)
		return;
	jQuery.selectcheckApply.apply(jQuery.selectdrug, [e]);
};
jQuery.selectcheckApply = function(e)
{
	if(!jQuery.selectdrug)
		return;
	var pointer = jQuery.iUtil.getPointer(e);
	
	var scr = jQuery.iUtil.getScroll(jQuery.selectdrug);
	pointer.x += scr.l - this.f.scr.l - this.f.pos.x;
	pointer.y += scr.t - this.f.scr.t - this.f.pos.y;
	
	var sx = Math.min(pointer.x, this.f.pointer.x);
	var sw = Math.min(Math.abs(pointer.x - this.f.pointer.x), Math.abs(this.f.scr.w - sx));
	var sy = Math.min(pointer.y, this.f.pointer.y);
	var sh = Math.min(Math.abs(pointer.y - this.f.pointer.y), Math.abs(this.f.scr.h - sy));
	if (this.scrollTop > 0 && pointer.y - 20 < this.scrollTop) {
		var diff = Math.min(scr.t, 10);
		sy -= diff;
		sh += diff;
		this.scrollTop -= diff;
	} else if (this.scrollTop+ this.f.pos.h < this.f.scr.h && pointer.y + 20 > this.scrollTop + this.f.pos.h) {
		var diff = Math.min(this.f.scr.h - this.scrollTop, 10);
		this.scrollTop += diff;
		if (this.scrollTop != scr.t)
			sh += diff;
	}
	if (this.scrollLeft > 0 && pointer.x - 20 < this.scrollLeft) {
		var diff = Math.min(scr.l, 10);
		sx -= diff;
		sw += diff;
		this.scrollLeft -= diff;
	} else if (this.scrollLeft+ this.f.pos.w < this.f.scr.w && pointer.x + 20 > this.scrollLeft + this.f.pos.w) {
		var diff = Math.min(this.f.scr.w - this.scrollLeft, 10);
		this.scrollLeft += diff;
		if (this.scrollLeft != scr.l)
			sw += diff;
	}
	jQuery.selectHelper.css(
		{
			left:	sx + 'px',
			top:	sy + 'px',
			width:	sw + 'px',
			height:	sh + 'px'
		}
	);
	jQuery.selectHelper.l = sx + this.f.scr.l;
	jQuery.selectHelper.t = sy + this.f.scr.t;
	jQuery.selectHelper.r = jQuery.selectHelper.l + sw;
	jQuery.selectHelper.b = jQuery.selectHelper.t + sh;

	jQuery.selectedone = false;
	this.f.el.each(
		function () {
			// Locate the current element in the current selection
			iIndex = jQuery.selectCurrent.indexOf(jQuery.attr(this, 'id'));
			// In case we are currently OVER an item
			if (
				! ( this.pos.x > jQuery.selectHelper.r
				|| (this.pos.x + this.pos.wb) < jQuery.selectHelper.l
				|| this.pos.y > jQuery.selectHelper.b
				|| (this.pos.y + this.pos.hb) < jQuery.selectHelper.t
				)
			)
			{
				jQuery.selectedone = true;
				if (this.s != true) {
					this.s = true;
					jQuery(this).addClass(jQuery.selectdrug.f.sc);
				}

				// Check to see if this item was previously selected, if so, unselect it
				if (iIndex != -1) {
					this.s = false;
					jQuery(this).removeClass(jQuery.selectdrug.f.sc);
				}
			} else if (
						(this.s == true) &&
						(iIndex == -1)
					) {
				// If the item was marked as selected, but it was not selected when you started dragging unselect it.
				this.s = false;
				jQuery(this).removeClass(jQuery.selectdrug.f.sc);
			} else if (
						(!this.s) &&
						(jQuery.selectKeyHelper == true) &&
						(iIndex != -1)
					) {
				// Reselect the item if:
				// - we ARE multiselecting,
				// - dragged over an allready selected object (so it got unselected)
				// - But then dragged the selection out of it again.
				this.s = true;
				jQuery(this).addClass(jQuery.selectdrug.f.sc);
			}
		}
	);
	return false;
};
jQuery.selectstop = function(e)
{
	if(!jQuery.selectdrug)
		return;
	jQuery.selectstopApply.apply(jQuery.selectdrug, [e]);
};
jQuery.selectstopApply = function(e)
{
	jQuery(document)
		.unbind('mousemove', jQuery.selectcheck)
		.unbind('mouseup', jQuery.selectstop);
	if(!jQuery.selectdrug)
		return;
	jQuery.selectHelper.css('display','none');
	if (this.f.hc)
		jQuery.selectHelper.removeClass(this.f.hc);
	jQuery.selectdrug = false;
	jQuery('body').append(jQuery.selectHelper.get(0));

        /* added by Roman Plessl -- rp */
        mySelectTop     = jQuery.selectHelper.t;      
        mySelectLeft    = jQuery.selectHelper.l;
        mySelectRight   = jQuery.selectHelper.r;
        mySelectBottom  = jQuery.selectHelper.b;

        changeRRDImage();

	// In case we have selected some new items..
	if (jQuery.selectedone == true) {
		if (this.f.onselect)
			this.f.onselect(jQuery.Selectserialize(jQuery.attr(this,'id')));
	} else {
		if (this.f.onselectstop)
			this.f.onselectstop(jQuery.Selectserialize(jQuery.attr(this,'id')));
	}
	// Reset current selection
	jQuery.selectCurrent = [];
};

jQuery.Selectserialize = function(s)
{
	var h = '';
	var o = [];
	if (a = jQuery('#' + s)) {
		a.get(0).f.el.each(
			function ()
			{
				if (this.s == true) {
					if (h.length > 0) {
						h += '&';
					}
					h += s + '[]=' + jQuery.attr(this,'id');
					o[o.length] = jQuery.attr(this,'id');
				}
			}
		);
	}
	return {hash:h, o:o};
};
jQuery.fn.Selectable = function(o)
{
	if (!jQuery.selectHelper) {
		jQuery('body',document).append('<div id="selectHelper"></div>').bind('keydown', jQuery.selectKeyDown).bind('keyup', jQuery.selectKeyUp);
		jQuery.selectHelper = jQuery('#selectHelper');
		jQuery.selectHelper.css(
			{
				position:	'absolute',
				display:	'none'
			}
		);

		if (window.event) {
			jQuery('body',document).bind('keydown', jQuery.selectKeyDown).bind('keyup', jQuery.selectKeyUp);
		} else {
			jQuery(document).bind('keydown', jQuery.selectKeyDown).bind('keyup', jQuery.selectKeyUp);
		}
	}

    if (!o) {
		o = {};
	}
    return this.each(
		function()
		{
			if (this.isSelectable)
				return;
			this.isSelectable = true;
			this.f = {
				a : o.accept,
				o : o.opacity ? parseFloat(o.opacity) : false,
				sc : o.selectedclass ? o.selectedclass : false,
				hc : o.helperclass ? o.helperclass : false,
				onselect : o.onselect ? o.onselect : false,
				onselectstop : o.onselectstop ? o.onselectstop : false
			};
			this.f.el = jQuery('.' + o.accept);
			jQuery(this).bind('mousedown', jQuery.selectstart).css('position', 'relative');
		}
	);
};

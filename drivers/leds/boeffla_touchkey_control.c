/*
 * 
 * Boeffla touchkey control OnePlus3/OnePlus2
 * 
 * Author: andip71 (aka Lord Boeffla)
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

/*
 * Change log:
 *
 * 1.3.1 (06.09.2017)
 *	- Corrections of some pr_debug functions
 * 
 * 1.3.0 (30.08.2017)
 *	- Adjust to stock handling, where by default display touch does not
 *    light up the touchkey lights anymore
 *
 * 1.2.0 (22.09.2016)
 *	- Change duration from seconds to milliseconds
 *
 * 1.1.0 (19.09.2016)
 *	- Add kernel controlled handling
 *
 * 1.0.0 (19.09.2016)
 *	- Initial version
 *
 *		Sys fs:
 *
 * 			/sys/class/misc/btk_control/btkc_mode
 *
 * 				0: touchkey and display
 * 				1: touch key buttons only (DEFAULT)
 * 				2: Off - touch key lights are always off
 *
 *
 * 			/sys/class/misc/btk_control/btkc_timeout
 *
 * 				timeout in seconds from 1 - 30
 * 				(0 = rom is taking care of the timeout - DEFAULT)
 *
 *
 * 			/sys/class/misc/btk_control/btkc_version
 *
 * 				display version of Boeffla touch key control driver
 *
 */

#include <linux/types.h>
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>
#include <linux/notifier.h>
#include <linux/kobject.h>
#include <linux/lcd_notify.h>
#include <linux/boeffla_touchkey_control.h>


/*****************************************/
// Declarations
/*****************************************/

int btkc_mode    = MODE_TOUCHKEY_ONLY;		// touchkey only is default
int btkc_timeout = TIMEOUT_DEFAULT;			// default is rom controlled timeout

int isScreenTouched = 0;
int cacheBrightness = BRIGHTNESS_DEFAULT;

static struct notifier_block lcd_notif;

static void led_work_func(struct work_struct *unused);
static DECLARE_DELAYED_WORK(led_work, led_work_func);


/*****************************************/
// internal functions
/*****************************************/

static void led_work_func(struct work_struct *unused)
{
	pr_debug("Boeffla touch key control: timeout over, disable touchkey led\n");

	// switch off LED and cancel any scheduled work
	qpnp_boeffla_set_button_backlight(BRIGHTNESS_OFF);
	cancel_delayed_work(&led_work);
}


static int lcd_notifier_callback(struct notifier_block *this,
								unsigned long event, void *data)
{
	switch (event)
	{
		case LCD_EVENT_OFF_START:
			pr_debug("Boeffla touch key control: screen off detected, disable touchkey led\n");
			
			// switch off LED and cancel any scheduled work
			qpnp_boeffla_set_button_backlight(BRIGHTNESS_OFF);
			cancel_delayed_work(&led_work);
			break;

		case LCD_EVENT_ON_START:
			pr_debug("Boeffla touch key control: screen on detected\n");

			// only if in touchkey+display mode, or touchkey_only but with kernel controlled
			// timeout, switch on LED and schedule work to switch it off again
			if ((btkc_mode == MODE_TOUCHKEY_DISP) ||
				((btkc_mode == MODE_TOUCHKEY_ONLY) && (btkc_timeout != 0)))
			{
				qpnp_boeffla_set_button_backlight(cacheBrightness);

				cancel_delayed_work(&led_work);
				schedule_delayed_work(&led_work, msecs_to_jiffies(btkc_timeout));
			}

		default:
			break;
	}

	return 0;
}


/*****************************************/
// exported functions
/*****************************************/

void btkc_touch_start()
{
	pr_debug("Boeffla touch key control: display touch start detected\n");

	isScreenTouched = 1;
	
	// only if in touchkey+display mode, switch LED on and cancel any scheduled work
	if (btkc_mode == MODE_TOUCHKEY_DISP)
	{
		qpnp_boeffla_set_button_backlight(cacheBrightness);
		cancel_delayed_work(&led_work);
	}
}


void btkc_touch_stop()
{
	pr_debug("Boeffla touch key control: display touch stop detected\n");

	isScreenTouched = 0;

	// only if in touchkey+display mode, schedule work to switch it off again
	if (btkc_mode == MODE_TOUCHKEY_DISP)
	{
		cancel_delayed_work(&led_work);
		schedule_delayed_work(&led_work, msecs_to_jiffies(btkc_timeout));
	}
}


void btkc_touch_button()
{
	pr_debug("Boeffla touch key control: touch button detected\n");

	// only if in touchkey+display mode, or touchkey_only but with kernel controlled
	// timeout, switch on LED and schedule work to switch it off again
	if ((btkc_mode == MODE_TOUCHKEY_DISP) ||
		((btkc_mode == MODE_TOUCHKEY_ONLY) && (btkc_timeout != 0)))
 	{
 		qpnp_boeffla_set_button_backlight(cacheBrightness);

 		cancel_delayed_work(&led_work);
 		schedule_delayed_work(&led_work, msecs_to_jiffies(btkc_timeout));
 	}
}


// hook function for led_set routine in leds-qpnp driver
int btkc_led_set(int val)
{
	pr_debug("Boeffla touch key control: touch button detected\n");

	// cache button backlight brightness
	if (val != BRIGHTNESS_OFF)
		cacheBrightness = val;

	// rom is only allowed to control LED when in touchkey_only mode
	// and no kernel based timeout
	if ((btkc_mode != MODE_TOUCHKEY_ONLY) || 
		((btkc_mode == MODE_TOUCHKEY_ONLY) && (btkc_timeout != 0)))
		return -1;

	return val;
}


/*****************************************/
// sysfs interface functions
/*****************************************/

static ssize_t btkc_mode_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "Mode: %d\n", btkc_mode);
}


static ssize_t btkc_mode_store(struct device *dev, struct device_attribute *attr,
						const char *buf, size_t count)
{
	unsigned int ret = -EINVAL;
	unsigned int val;

	// check data and store if valid
	ret = sscanf(buf, "%d", &val);

	if (ret != 1)
		return -EINVAL;

	if ((val >= MODE_TOUCHKEY_DISP) || (val <= MODE_OFF))
	{
		btkc_mode = val;

		// reset LED after every mode change
		cancel_delayed_work(&led_work);
		qpnp_boeffla_set_button_backlight(BRIGHTNESS_OFF);
	}

	return count;
}


static ssize_t btkc_timeout_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "Timeout [s]: %d\n", btkc_timeout);
}


static ssize_t btkc_timeout_store(struct device *dev, struct device_attribute *attr,
						const char *buf, size_t count)
{
	unsigned int ret = -EINVAL;
	unsigned int val;

	// check data and store if valid
	ret = sscanf(buf, "%d", &val);

	if (ret != 1)
		return -EINVAL;

	if ((val >= TIMEOUT_MIN) || (val <= TIMEOUT_MAX))
	{
		btkc_timeout = val;

		// temporary: help migration from seconds to milliseconds
		if (btkc_timeout <= 30)
			btkc_timeout = btkc_timeout * 1000;

		// reset LED after every timeout change
		cancel_delayed_work(&led_work);
		qpnp_boeffla_set_button_backlight(BRIGHTNESS_OFF);
	}

	return count;
}


static ssize_t btkc_version_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%s\n", BTK_CONTROL_VERSION);
}


/***************************************************/
// Initialize boeffla touch key control sysfs folder
/***************************************************/

// define objects
static DEVICE_ATTR(btkc_mode, 0664, btkc_mode_show, btkc_mode_store);
static DEVICE_ATTR(btkc_timeout, 0664, btkc_timeout_show, btkc_timeout_store);
static DEVICE_ATTR(btkc_version, 0664, btkc_version_show, NULL);

// define attributes
static struct attribute *btkc_attributes[] = {
	&dev_attr_btkc_mode.attr,
	&dev_attr_btkc_timeout.attr,
	&dev_attr_btkc_version.attr,
	NULL
};

// define attribute group
static struct attribute_group btkc_control_group = {
	.attrs = btkc_attributes,
};

// define control device
static struct miscdevice btkc_device = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "btk_control",
};


/*****************************************/
// Driver init and exit functions
/*****************************************/

static int btk_control_init(void)
{
	// register boeffla touch key control device
	misc_register(&btkc_device);
	if (sysfs_create_group(&btkc_device.this_device->kobj,
				&btkc_control_group) < 0) {
		printk("Boeffla touch key control: failed to create sys fs object.\n");
		return 0;
	}

	// register callback for screen on/off notifier
	lcd_notif.notifier_call = lcd_notifier_callback;
	if (lcd_register_client(&lcd_notif) != 0)
		pr_err("%s: Failed to register lcd callback\n", __func__);

	// Print debug info
	printk("Boeffla touch key control: driver version %s started\n", BTK_CONTROL_VERSION);
	return 0;
}


static void btk_control_exit(void)
{
	// remove boeffla touch key control device
	sysfs_remove_group(&btkc_device.this_device->kobj,
                           &btkc_control_group);

	// cancel and flush any remaining scheduled work
	cancel_delayed_work(&led_work);
	flush_scheduled_work();

	// unregister screen notifier
	lcd_unregister_client(&lcd_notif);

	// Print debug info
	printk("Boeffla touch key control: driver stopped\n");
}


/* define driver entry points */
module_init(btk_control_init);
module_exit(btk_control_exit);

MODULE_AUTHOR("andip71");
MODULE_DESCRIPTION("boeffla touch key control");
MODULE_LICENSE("GPL v2");

# buyitem.pl
#
# Routines for purchasing products with both keyboard input (buy_win) and 
# barcode input (buy_single_item_with_scanner).
#
# $Id: buyitem.pl,v 1.18 2001-06-08 18:28:25 bob Exp $
#

require "$BOBPATH/bob_db.pl";
require "$BOBPATH/dlg.pl";
require "$BOBPATH/speech.pl";
require "$BOBPATH/profile.pl";
require "$BOBPATH/bc_util.pl";

$PRICES{"Candy/Can of Soda"} = 0.45;
$PRICES{"Juice"} = 0.70;
$PRICES{"Snapple"} = 0.80;
$PRICES{"Popcorn/Chips/etc."} = 0.30;

my $MAX_PURCHASE = 100;		# dollars


sub
buy_win
#
# Legacy routine for purchasing an item from one of the food categories
# in the PRICES array.  If 'type' is not found in PRICES then ask the 
# user to input the price of their purchase.  Return the name of the 
# product category on success; return blank string otherwise (user 
# canceled).
#
{
  my ($userid, $type) = @_;

  my $amt;
  my $confirmMsg;
  undef $amt;

  if (defined $PRICES{$type}) {
    $amt = $PRICES{$type};
    $confirmMsg = "Buy ${type}?";
  }

  if (! defined $amt) {
    $confirmMsg = "Purchase amount?";

    my $win_title = "Buy Stuff from Chez Bob";
    my $win_text = q{
What is the price of the item you are buying?
(NOTE: Be sure to include the decimal point!)};

    while (1) {
      if (system("$DLG --title \"$win_title\" --clear --cr-wrap --inputbox \"" .
                 $win_text .  "\" 10 50 2> $TMP/input.deposit") != 0) {
        return "";
      }

      $amt = `cat $TMP/input.deposit`;
      if ($amt =~ /^\d+$/ || $amt =~ /^\d*\.\d{0,2}$/) {
        if ($amt > $MAX_PURCHASE) {
          &exceed_max_purchase_win;
        } else {
          # amt entered is OK
          last;
        }
      } else {
        &invalid_purchase_win;
      }
    }  # while
    &sayit(&format_money($amt));

  } else {
    if ($PROFILE{"Speech"}) { 
      my $phonetic_name = $type;
      my $slashpos = index($type, "/");
      if ($slashpos > 0) {  
        $phonetic_name = substr($type, 0, $slashpos);
      }
      &sayit("$phonetic_name"); 
    }
  }

  if (! $PROFILE{"No Confirmation"}) {
    if (! &confirm_win($confirmMsg,
                     sprintf("\nIs your purchase amount \\\$%.2f?", $amt),40)) {
      return "";
    }
  }

  my $buy = $PROFILE{"Privacy"} ? "BUY" : $type;
  &bob_db_update_balance($userid, -$amt, $buy);

  return $type;
}


sub
buy_single_item_with_scanner
#
# Look up 'prodbarcode' from the products table and update the product's 
# stock (-1) and the user's balance.  On failure (product does not
# exist or user cancels) return empty string; on success (user buys product)
# return the name of the product purchased.  
#
{
  my ($userid, $prodbarcode) = @_;

  # Check for the magic 'shell access' barcode
  if ($prodbarcode eq '898972437')
  {
    # Alan Su  -- 1001
    # Mike C.  -- 1174
    # John Bellardo -- 1181
    # Marvin McNett -- 1191
    if ($userid != 1001 && $userid != 1174 &&
        $userid != 1181 && $userid != 1191 )
    {
      return "";
    }

    if ($main::drop_to_shell == 0)
    {
        $main::drop_to_shell = $userid;
        if ($PROFILE{"Speech"}) { &sayit("Thank you for taking such good care of chay bob"); }
    }
    else
    {
        $main::drop_to_shell = 0;
        if ($PROFILE{"Speech"}) { &sayit("i regret your decision not to take care of me"); }
    }
    return "";
  }

  $barcode = &preprocess_barcode($prodbarcode);      
  $prodname = &bob_db_get_productname_from_barcode($barcode);
  if (!defined $prodname) {
    &invalid_product_barcode_win;
    return "";
  }

  my $phonetic_name = &bob_db_get_phonetic_name_from_barcode($barcode);
  if ($PROFILE{"Speech"}) { &sayit("$phonetic_name"); }
  my $amt = &bob_db_get_price_from_barcode($barcode);
  my $txt = sprintf("\nIs your purchase amount \\\$%.2f?", $amt);

  if (! $PROFILE{"No Confirmation"}) {
    if (! &confirm_win($prodname, $txt, 40)) {
      return "";
    }
  }

  &bob_db_update_stock(-1, $prodname);
  my $type = $PROFILE{"Privacy"} ? "BUY" : "BUY $prodname";
  &bob_db_update_balance($userid, -$amt, $type);

  return $prodname;
}


sub
buy_with_cash
#
# Call get_barcode_win to get item barcode, look it up and update 
# the product's stock (-1).  On failure (product does not
# exist or user cancels) return empty string; on success (user buys product)
# return the name of the product purchased.  
#
{
  my $msg = q{
You are paying with cash.  Please deposit the 
appropriate amount in the Bank of Bob and 
scan the product's barcode now.};
  my $barcode = &get_barcode_win($msg, 50, 11); 
  if (!defined $barcode) {
    # user canceled
    return "";
  }

  $barcode = &preprocess_barcode($barcode);      
  $prodname = &bob_db_get_productname_from_barcode($barcode);
  if (!defined $prodname) {
    &invalid_product_barcode_win;
    return "";
  }

  my $phonetic_name = &bob_db_get_phonetic_name_from_barcode($barcode);
  &sayit("$phonetic_name");

  &bob_db_update_stock(-1, $prodname);

  return $prodname;
}


sub
invalid_product_barcode_win
{
  my $win_title = "Invalid Product";
  my $win_text = q{
This is an invalid product barcode.};

  system("$DLG --title \"$win_title\" --cr-wrap --msgbox \"" .
	 $win_text .  "\" 7 42 2> /dev/null");
}


sub
exceed_max_purchase_win
{
  my $win_title = "Invalid amount";
  my $win_text = "\nThe maximum purchase amount is \\\$$MAX_PURCHASE";

  system("$DLG --title \"$win_title\" --cr-wrap --msgbox \"" .
         $win_text .  "\" 7 40 2> /dev/null");
}


sub
invalid_purchase_win
{
  my $win_title = "Invalid amount";
  my $win_text = q{
Valid amounts are positive numbers with up
to two decimal places of precision.};

  system("$DLG --title \"$win_title\" --cr-wrap --msgbox \"" .
         $win_text .  "\" 8 50 2> /dev/null");
}


1;

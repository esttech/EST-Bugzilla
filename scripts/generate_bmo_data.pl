#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::User;
use Bugzilla::User::APIKey;
use Bugzilla::Install;
use Bugzilla::Milestone;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Group;
use Bugzilla::Version;
use Bugzilla::Constants;
use Bugzilla::Keyword;
use Bugzilla::Config qw(:admin);
use Bugzilla::User::Setting;
use Bugzilla::Status;

use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Value;
use Bugzilla::Extension::TrackingFlags::Flag::Visibility;

use Getopt::Long qw( :config gnu_getopt );

BEGIN { Bugzilla->extensions }

my $dbh = Bugzilla->dbh;

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

##########################################################################
#  Set Default User Preferences
##########################################################################

my %user_prefs = (
  post_bug_submit_action => 'nothing',
  bugmail_new_prefix     => 'on',
  comment_box_position   => 'after_comments',
  comment_sort_order     => 'oldest_to_newest',
  csv_colsepchar         => ',',
  display_quips          => 'off',
  email_format           => 'text_only',
  headers_in_body        => 'off',
  inline_history         => 'on',
  lang                   => 'en',
  orange_factor          => 'off',
  per_bug_queries        => 'off',
  possible_duplicates    => 'on',
  post_bug_submit_action => 'same_bug',
  product_chooser        => 'pretty_product_chooser',
  quicksearch_fulltext   => 'off',
  quote_replies          => 'quoted_reply',
  requestee_cc           => 'on',
  request_nagging        => 'on',
  show_gravatars         => 'On',
  show_my_gravatar       => 'On',
  skin                   => 'Mozilla',
  state_addselfcc        => 'cc_unless_role',
  timezone               => 'local',
  zoom_textareas         => 'off',
);

my %opt_param;
GetOptions('user-pref=s%' => \%user_prefs, 'param=s' => \%opt_param);

my $admin_email = shift || 'kraken@est.tech';
Bugzilla->set_user(Bugzilla::User->check({name => $admin_email}));

foreach my $pref (keys %user_prefs) {
  my $value = $user_prefs{$pref};
  Bugzilla::User::Setting::set_default($pref, $value, 1);
}

############################################################
# OS, Platform, Priority, Severity
############################################################

my @priorities = qw(
  Priority1
  --
);

if (!$dbh->selectrow_array("SELECT 1 FROM priority WHERE value = 'Priority1'")) {
  $dbh->do("DELETE FROM priority");
  my $count = 1;
  foreach my $priority (@priorities) {
    $dbh->do("INSERT INTO priority (value, sortkey) VALUES (?, ?)",
      undef, ($priority, $count));
    $count++;
  }
}

my @platforms = qw(
  RCS_G5
  RCS_G4
  RCS_G3
  RCS_Common
  RCS_G2
  General
  Other
  All
);

if (!$dbh->selectrow_array("SELECT 1 FROM rep_platform WHERE value = 'RCS_G5'")) {
  $dbh->do("DELETE FROM rep_platform");
  my $count = 100;
  foreach my $platform (@platforms) {
    $dbh->do("INSERT INTO rep_platform (value, sortkey) VALUES (?, ?)",
      undef, ($platform, $count + 100));
  }
}

my @oses = (
  'All',
  'Linux',
);

if (!$dbh->selectrow_array("SELECT 1 FROM op_sys WHERE value = 'AIX'")) {
  $dbh->do("DELETE FROM op_sys");
  my $count = 100;
  foreach my $os (@oses) {
    $dbh->do("INSERT INTO op_sys (value, sortkey) VALUES (?, ?)",
      undef, ($os, $count + 100));
  }
}

my @severities = qw(
  Severe
  High
  Medium
  Low
);

if (!$dbh->selectrow_array("SELECT 1 FROM bug_severity WHERE value = 'Severe'")) {
  my $count = 1;
  foreach my $severity (@severities) {
    $dbh->do("INSERT INTO bug_severity (value, sortkey) VALUES (?, ?)",
      undef, ($severity, $count));
    $count++;
  }
}

##########################################################################
# Create Users
##########################################################################
# First of all, remove the default .* regexp for the editbugs group.
my $group = new Bugzilla::Group({name => 'editbugs'});
$group->set_user_regexp('');
$group->update();

my @users = (
  {
    login    => 'nobody@mozilla.org',
    realname => 'Nobody; OK to take it and work on it',
    password => '*'
  },
  {
    login    => 'bugzilla@est.tech',
    realname => 'Bugzilla; A dummy id',
    password => '*'
  },  

  map { {login => $_, realname => (split(/@/, $_, 2))[0], password => '*',} }
    map {
    map {@$_}
      values %$_
    } values %Bugzilla::Extension::BMO::Data::group_auto_cc,
);

print "creating user accounts...\n";
foreach my $user (@users) {
  if (is_available_username($user->{login})) {
    my $new_user = Bugzilla::User->create({
      login_name    => $user->{login},
      realname      => $user->{realname},
      cryptpassword => $user->{password},
    });
    if ($user->{admin}) {
      Bugzilla::Install::make_admin($user->{login});
    }
    if (exists $user->{api_key}) {
      Bugzilla::User::APIKey->create_special({
        user_id     => $new_user->id,
        description => 'API key for Test User',
        api_key     => $user->{api_key}
      });
    }
  }
}

##########################################################################
# Create Classifications
##########################################################################
my @classifications = (
  {
    name        => "ELIN Software",
    description => "ELIN stuff"
  },
  {name => "Graveyard", description => "Old, retired products"},
);

print "creating classifications...\n";
for my $class (@classifications) {
  my $new_class = Bugzilla::Classification->new({name => $class->{name}});
  if (!$new_class) {
    $dbh->do('INSERT INTO classifications (name, description) VALUES (?, ?)',
      undef, ($class->{name}, $class->{description}));
  }
}

##########################################################################
# Create Some Products
##########################################################################
my @products = (
  {
    classification => 'ELIN Software',
    product_name   => 'ELIN',
    description    => 'For bugs in ELIN '
      . 'here or in the <a href="https://www.est.tech">EST</a> product.'
      . '(<a href="https://www.est.tech">more info</a>)',
    versions =>
      ['unspecified'],
    default_version  => 'unspecified',
    milestones => [
      '---',
    ],
    defaultmilestone => '---',
    components       => [{
      name        => 'KernelSpace',
      description => 'For bugs in ELIN Kernel space',
      initialowner   => 'bugzilla@est.tech',
      initialqaowner => '',
      initial_cc     => [],
      watch_user     => 'bugzilla@est.tech',
      team_name      => 'ELIN',
      triage_owner   => 'bugzilla@est.tech',
    },
    {
      name        => 'UserSpace',
      description => 'For bugs in ELIN user space',
      initialowner   => 'bugzilla@est.tech',
      initialqaowner => '',
      initial_cc     => [],
      watch_user     => 'bugzilla@est.tech',
      team_name      => 'ELIN',
      triage_owner   => 'bugzilla@est.tech',
    },
    {
      name        => 'ELINInfra',
      description => 'For bugs in ELIN infra',
      initialowner   => 'bugzilla@est.tech',
      initialqaowner => '',
      initial_cc     => [],
      watch_user     => 'bugzilla@est.tech',
      team_name      => 'ELIN',
      triage_owner   => 'bugzilla@est.tech',
    }],
  },
);

my $default_op_sys_id
  = $dbh->selectrow_array("SELECT id FROM op_sys WHERE value = 'Unspecified'");
my $default_platform_id = $dbh->selectrow_array(
  "SELECT id FROM rep_platform WHERE value = 'Unspecified'");

print "creating products...\n";
for my $product (@products) {
  my $new_product = Bugzilla::Product->new({name => $product->{product_name}});
  if (!$new_product) {
    my $class_id = 1;
    if ($product->{classification}) {
      $class_id
        = Bugzilla::Classification->new({name => $product->{classification}})->id;
    }
    $dbh->do(
      'INSERT INTO products (name, description, classification_id,
                             default_op_sys_id, default_platform_id, default_version)
                  VALUES (?, ?, ?, ?, ?, ?)',
      undef,
      (
        $product->{product_name}, $product->{description},
        $class_id,                $default_op_sys_id,
        $default_platform_id,     $product->{default_version}
      )
    );

    $new_product = new Bugzilla::Product({name => $product->{product_name}});

    $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?, ?)',
      undef, ($new_product->id, $product->{defaultmilestone}));

    $dbh->do('INSERT INTO versions (product_id, value) VALUES (?, ?)',
      undef, ($new_product->id, $product->{default_version}));

    # Now clear the internal list of accessible products.
    delete Bugzilla->user->{selectable_products};

    foreach my $component (@{$product->{components}}) {
      print "creating product...\n";

      if (!Bugzilla::User->new({name => $component->{watch_user}})) {
        Bugzilla::User->create({
          login_name => $component->{watch_user}, cryptpassword => '*',
        });
      }
      Bugzilla->input_params({watch_user => $component->{watch_user}});
      Bugzilla::Component->create({
        name             => $component->{name},
        product          => $new_product,
        description      => $component->{description},
        initialowner     => $component->{initialowner},
        initialqacontact => $component->{initialqacontact} || '',
        initial_cc       => $component->{initial_cc} || [],
        team_name        => 'ELIN',
        triage_owner_id  => $component->{triage_owner} || '',
      });
    }
  }

  foreach my $version (@{$product->{versions}}) {
    if (!new Bugzilla::Version({name => $version, product => $new_product})) {
      Bugzilla::Version->create({value => $version, product => $new_product});
    }
  }

  foreach my $milestone (@{$product->{milestones}}) {
    if (!new Bugzilla::Milestone({name => $milestone, product => $new_product})) {
      $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?,?)',
        undef, $new_product->id, $milestone);
    }
  }
}

##########################################################################
# Create Groups
##########################################################################
my @groups = (
  {
    name         => 'core-security',
    description  => 'Security-Sensitive Core Bug',
    no_admin     => 1,
    bug_group    => 1,
    all_products => 1,
  },
  {
    name => 'can_restrict_comments',
    description =>
      'Members of this group will be able to restrict comments on bugs',
    no_admin     => 0,
    all_products => 0,
    bug_group    => 0,
  },
  {
    name         => 'timetrackers',
    description  => 'Time Trackers',
    no_admin     => 1,
    all_products => 0,
    bug_group    => 0,
  },
  {
    name => 'can_triage_bugs',
    description  => 'Can triage bugs (via the "triaged" keyword)',
    no_admin     => 0,
    all_products => 0,
    bug_group    => 0,
  },
  {
    name => 'edittrackingflags',
    description  => 'Edit Tracking Flags Group',
    no_admin     => 0,
    all_products => 0,
    bug_group    => 0,
  },
);

print "creating groups...\n";
foreach my $group (@groups) {
  my $name      = $group->{name};
  my $desc      = $group->{desc};
  my $bug_group = exists $group->{bug_group} ? $group->{bug_group} : 1;
  my $no_admin  = exists $group->{no_admin} ? $group->{no_admin} : 0;

  if (!Bugzilla::Group->new({name => $name})) {
    my $new_group;
    if (exists $group->{no_admin} && $group->{no_admin}) {
      $dbh->do(
            'INSERT INTO '
          . $dbh->quote_identifier('groups')
          . ' (name, description, isbuggroup, isactive)
                      VALUES (?, ?, 1, 1)', undef,
        ($group->{name}, $group->{description})
      );
      $new_group = Bugzilla::Group->new({name => $group->{name}});
    }
    else {
      $new_group = Bugzilla::Group->create({
        name        => $group->{name},
        description => $group->{description},
        isbuggroup  => $group->{bug_group}
      });
    }

    if (exists $group->{all_products} && $group->{all_products}) {
      $dbh->do(
        'INSERT INTO group_control_map
                     (group_id, product_id, entry, membercontrol, othercontrol, canedit)
                     SELECT ?, products.id, 0, ?, ?, 0 FROM products', undef,
        ($new_group->id, CONTROLMAPSHOWN, CONTROLMAPSHOWN)
      );
    }
  }
}

my @fields = ({
  name         => 'cf_due_date',
  description  => 'Due Date',
  type         => FIELD_TYPE_DATE,
  sortkey      => 949,
  mailhead     => 0,
  enter_bug    => 1,
  obsolete     => 0,
  custom       => 1,
  buglist      => 1,
  reverse_desc => "",
  is_mandatory => 0,
});

say 'creating custom fields';
foreach my $field (@fields) {
  next if Bugzilla::Field->new({name => $field->{name}});
  my $field_obj = Bugzilla::Field->create({
    name                => $field->{name},
    description         => $field->{description},
    type                => $field->{type},
    sortkey             => $field->{sortkey},
    mailhead            => $field->{new_bugmail},
    enter_bug           => $field->{enter_bug},
    obsolete            => $field->{obsolete},
    custom              => 1,
    buglist             => 1,
    visibility_field_id => $field->{visibility_field_id},
    visibility_values   => $field->{visibility_values},
    value_field_id      => $field->{value_field_id},
    reverse_desc        => $field->{reverse_desc},
    is_mandatory        => $field->{is_mandatory},
  });
}


# Update default security group settings for new products
my $default_security_group = Bugzilla::Group->new({name => 'core-security'});
if ($default_security_group) {
  $dbh->do(
    'UPDATE products SET security_group_id = ? WHERE security_group_id IS NULL',
    undef, $default_security_group->id);
}

##########################################################################
# Set Parameters
##########################################################################

my %set_params = (
  allowbugdeletion          => 1,
  allowuserdeletion         => 0,
  allow_attachment_deletion => 1,
  allow_attachment_display  => 1,
  bonsai_url                => 'http://bonsai.mozilla.org',
  collapsed_comment_tags =>
    'obsolete,spam,typo,me-too,advocacy,off-topic,offtopic,abuse,abusive',
  confirmuniqueusermatch => 0,
  maxusermatches         => '100',
  debug_group            => 'editbugs',
  default_bug_type       => 'Other',
  defaultpriority        => '--',         # FIXME: add priority
  defaultquery => 'resolution=---&emailassigned_to1=1&emailassigned_to2=1'
    . '&emailreporter2=1&emailqa_contact2=1&emailtype1=exact'
    . '&emailtype2=exact&order=Importance&keywords_type=allwords'
    . '&long_desc_type=substring',
  defaultseverity      => 'Low',
  edit_comments_group  => 'editbugs',
  github_pr_linking_enabled => 1,
  github_pr_signature_secret => 'B1gS3cret!',
  github_push_comment_enabled => 1,
  insidergroup         => 'core-security-release',
  last_change_time_non_bot_skip_list => 'automation@bmo.tld',
  last_visit_keep_days => '28',
  lxr_url              => 'http://mxr.mozilla.org/mozilla',
  lxr_root             => 'mozilla/',
  mail_delivery_method => 'Sendmail',
  mailfrom             => '"ELIN Bugzilla" <tracker@est.tech>',
  maintainer           => 'tracker@est.tech',
  maintainer_notices   => 'tracker@est.tech',
  maxattachmentsize    => '4096',
  maxusermatches       => '100',
  mostfreqthreshold    => '5',
  mybugstemplate       => 'buglist.cgi?bug_status=UNCONFIRMED&amp;bug_status=NEW'
    . '&amp;bug_status=ASSIGNED&amp;bug_status=REOPENED'
    . '&amp;emailassigned_to1=1&amp;emailreporter1=1'
    . '&amp;emailtype1=exact&amp;email1=%userid%'
    . '&amp;field0-0-0=bug_status&amp;type0-0-0=notequals'
    . '&amp;value0-0-0=UNCONFIRMED&amp;field0-0-1=reporter'
    . '&amp;type0-0-1=equals&amp;value0-0-1=%userid%',
  quip_list_entry_control        => 'moderated',
  password_complexity            => 'bmo',
  rate_limit_active              => 1,
  rate_limit_rules               => '{"get_attachments":[75,0],"get_comments":[75,0],"get_bug":[200,0],"show_bug":[120,0],"github":[10,0],"webpage_errors":[30,60]}',
  reminders_enabled              => 1,
  restrict_comments_group        => 'editbugs',
  restrict_comments_enable_group => 'can_restrict_comments',
  search_allow_no_criteria       => 0,
  strict_transport_security      => 'include_subdomains',
  timetrackinggroup              => 'timetrackers',
  upgrade_notification           => 'disabled',
  useclassification              => 1,
  usetargetmilestone             => 1,
  usestatuswhiteboard            => 1,
  usebugaliases                  => 1,
  useqacontact                   => 1,
  use_mailer_queue               => 1,
  user_info_class                => 'OAuth2,CGI',
  user_verify_class              => 'DB',
  %opt_param,
);

my $params_modified;
foreach my $param (keys %set_params) {
  my $value = $set_params{$param};
  next unless defined $value && Bugzilla->params->{$param} ne $value;
  SetParam($param, $value);
  $params_modified = 1;
}

write_params() if $params_modified;

##########################################################################
# Create flag types
##########################################################################
my @flagtypes = (
  {
    name             => 'review',
    desc             => 'The patch has passed review by a module owner or peer.',
    is_requestable   => 1,
    is_requesteeble  => 1,
    is_multiplicable => 1,
    grant_group      => '',
    target_type      => 'a',
    cc_list          => '',
    inclusions       => ['']
  },
);

print "creating flag types...\n";
foreach my $flag (@flagtypes) {
  next if new Bugzilla::FlagType({name => $flag->{name}});
  my $grant_group_id
    = $flag->{grant_group}
    ? Bugzilla::Group->new({name => $flag->{grant_group}})->id
    : undef;
  my $request_group_id
    = $flag->{request_group}
    ? Bugzilla::Group->new({name => $flag->{request_group}})->id
    : undef;

  $dbh->do(
    'INSERT INTO flagtypes (name, description, cc_list, target_type, is_requestable,
                                     is_requesteeble, is_multiplicable, grant_group_id, request_group_id)
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    undef,
    (
      $flag->{name},             $flag->{desc},
      $flag->{cc_list},          $flag->{target_type},
      $flag->{is_requestable},   $flag->{is_requesteeble},
      $flag->{is_multiplicable}, $grant_group_id,
      $request_group_id
    )
  );

  my $type_id = $dbh->bz_last_key('flagtypes', 'id');

  foreach my $inclusion (@{$flag->{inclusions}}) {
    my ($product, $component) = split(':', $inclusion);
    my ($prod_id, $comp_id);
    if ($product) {
      my $prod_obj = Bugzilla::Product->new({name => $product});
      $prod_id = $prod_obj->id;
      if ($component) {
        $comp_id
          = Bugzilla::Component->new({name => $component, product => $prod_obj})->id;
      }
    }
    $dbh->do(
      'INSERT INTO flaginclusions (type_id, product_id, component_id)
                  VALUES (?, ?, ?)', undef, ($type_id, $prod_id, $comp_id)
    );
  }
}

###########################################################
# Create bug status
###########################################################

my @statuses = (
  {
    value       => undef,
    transitions => [['NEW', 0]],
  },
  {
    value       => 'NEW',
    sortkey     => 100,
    isactive    => 1,
    isopen      => 1,
    transitions => [['IN_PROGRESS', 0], ['WAITING', 0], ['CANCELLED', 0], ['ONHOLD', 0]],
  },
  {
    value       => 'IN_PROGRESS',
    sortkey     => 200,
    isactive    => 1,
    isopen      => 1,
    transitions => [['WAITING', 0], ['CANCELLED', 0], ['ONHOLD', 0], ['IMPLEMENTED', 0]],
  },
  {
    value    => 'WAITING',
    sortkey  => 300,
    isactive => 1,
    isopen   => 1,
    transitions =>
      [['IN_PROGRESS', 0], ['CANCELLED', 0], ['ONHOLD', 0]],
  },  
  {
    value    => 'CANCELLED',
    sortkey  => 400,
    isactive => 1,
    isopen   => 0,
    transitions =>
      [],
  },
  {
    value       => 'IMPLEMENTED',
    sortkey     => 600,
    isactive    => 1,
    isopen      => 1,
    transitions => [ ['VERIFIED', 0], ['CANCELLED', 0]],
  },
  {
    value       => 'VERIFIED',
    sortkey     => 700,
    isactive    => 1,
    isopen      => 1,
    transitions => [['RESOLVED', 0],  ['CANCELLED', 0]],
  },
  {
    value       => 'ONHOLD',
    sortkey     => 800,
    isactive    => 1,
    isopen      => 1,
    transitions => [['WAITING', 0], ['IN_PROGRESS', 0], ['CANCELLED', 0]],
  }, 
  {
    value       => 'UNCONFIRMED',
    sortkey     => 900,
    isactive    => 1,
    isopen      => 1,
    transitions => [['NEW', 0]],
  },
  {
    value       => 'RESOLVED',
    sortkey     => 1000,
    isactive    => 1,
    isopen      => 1,
    transitions => [],
  },      
);

if (!$dbh->selectrow_array("SELECT 1 FROM bug_status WHERE value = 'NEW'"))
{
  $dbh->do('DELETE FROM bug_status');
  $dbh->do('DELETE FROM status_workflow');

  print "creating status workflow...\n";

  # One pass to add the status entries.
  foreach my $status (@statuses) {
    next if !$status->{value};
    $dbh->do(
      'INSERT INTO bug_status (value, sortkey, isactive, is_open) VALUES (?, ?, ?, ?)',
      undef,
      ($status->{value}, $status->{sortkey}, $status->{isactive}, $status->{isopen})
    );
  }

  # Another pass to add the transitions.
  foreach my $status (@statuses) {
    my $old_id;
    if ($status->{value}) {
      my $from_status = new Bugzilla::Status({name => $status->{value}});
      $old_id = $from_status->{id};
    }
    else {
      $old_id = undef;
    }

    foreach my $transition (@{$status->{transitions}}) {
      my $to_status = new Bugzilla::Status({name => $transition->[0]});

      $dbh->do(
        'INSERT INTO status_workflow (old_status, new_status, require_comment) VALUES (?, ?, ?)',
        undef,
        ($old_id, $to_status->{id}, $transition->[1])
      );
    }
  }
}

###########################################################
# Creating resolutions
###########################################################

my @resolutions = (
  {value => '',           sortkey => 100,  isactive => 1,},
  {value => 'RESOLVED',      sortkey => 200,  isactive => 1,},
  {value => 'CANCELLED',    sortkey => 300,  isactive => 1,},
);

if (!$dbh->selectrow_array(
  "SELECT 1 FROM resolution WHERE value = 'INCOMPLETE'"))
{
  $dbh->do('DELETE FROM resolution');
  print "creating resolutions...\n";
  foreach my $resolution (@resolutions) {
    next if !$resolution->{value};
    $dbh->do('INSERT INTO resolution (value, sortkey, isactive) VALUES (?, ?, ?)',
      undef, ($resolution->{value}, $resolution->{sortkey}, $resolution->{isactive}));
  }
}

###########################################################
# Create Keywords
###########################################################

my @keywords = (
  {
    name        => 'regression',
    description => 'The problem was fixed, but then it came back (regressed) '
      . 'and this new bug was filed to track the regression.'
  },
);

print "creating keywords...\n";
foreach my $kw (@keywords) {
  next if new Bugzilla::Keyword({name => $kw->{name}});
  Bugzilla::Keyword->create($kw);
}

###########################################################
# Create Tracking Flags
###########################################################

print "creating tracking flags...\n";
my @tracking_flags = (
  {
    name        => 'cf_status_ELIN',
    description => 'status-elin',
    sortkey     => 0,
    type        => 'tracking',
    enter_bug   => 1,
    is_active   => 1,
    values      => ['---', '?', 'affected', 'unaffected', 'fixed', 'wontfix', 'disabled'],
    products    => ['ELIN'],
  },
);

my $setter_group = Bugzilla::Group->new({name => 'editbugs'});

foreach my $flag_data (@tracking_flags) {
  my $values   = delete $flag_data->{values};
  my $products = delete $flag_data->{products};

  my $flag_obj = Bugzilla::Extension::TrackingFlags::Flag->new({name => $flag_data->{name}});
  next if $flag_obj; # Skip if already exists

  $flag_obj = Bugzilla::Extension::TrackingFlags::Flag->create($flag_data);

  # Add values for the new tracking flag
  my $sortkey = 0;
  foreach my $value (@{$values}) {
    $sortkey += 1;

    my $value_data = {
      value           => $value,
      setter_group_id => $setter_group->id,
      is_active       => 1,
      sortkey         => $sortkey,
      comment          => '',
      tracking_flag_id => $flag_obj->flag_id,
    };

    Bugzilla::Extension::TrackingFlags::Flag::Value->create($value_data);
  }

  # Make if visible to the products listed
  foreach my $product (@{$products}) {
    my $product_obj = Bugzilla::Product->new({name => $product});
    Bugzilla::Extension::TrackingFlags::Flag::Visibility->create({
      tracking_flag_id => $flag_obj->flag_id,
      product_id       => $product_obj->id,
      component_id     => undef,
    });
  }
}

print "installation and configuration complete!\n";

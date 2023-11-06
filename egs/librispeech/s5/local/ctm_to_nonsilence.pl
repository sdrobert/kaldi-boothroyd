#! /usr/bin/env perl

use strict;
use Getopt::Long;
use Pod::Usage;

Getopt::Long::Configure ("bundling");

my ($help, $man, $frame_shift, $samp_rate, $print_as, $sil) =
  (0, 0, 0.01, 16000, "sec", "<eps>");

GetOptions(
  'help' => \$help,
  'man' => \$man,
  'frame-shift=f' => \$frame_shift,
  'samp-rate=i' => \$samp_rate,
  'print-as=s' => \$print_as,
  "sil=s", \$sil) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

($frame_shift > 0) or die("$0: --frame-shift non-positive\n");
($samp_rate > 0) or die("$0: --samp-rate non-positive\n");

my ($fmt, $scale);
if ($print_as eq "sec") {
  my $prec = int(-log($frame_shift)/log(10)) + 1;
  ($fmt, $scale) = ("%.${prec}f %.${prec}f", 1);
} else {
  $fmt = "%d %d";
  if ($print_as eq "frame") {
    $scale = 1 / $frame_shift;
  } elsif ($print_as eq "samp") {
    $scale = $samp_rate;
  } else {
    die("$0: invalid --print-as (should be samp|frame|sec)\n")
  }
}

my ($ctm_file, $ctm_fn);
if (@ARGV == 0) {
  ($ctm_file, $ctm_fn) = (\*STDIN, "stdin");
} else {
  $ctm_fn = shift @ARGV;
  open($ctm_file, "<", $ctm_fn)
    or die("$0: Could not open '$ctm_fn' for reading\n");
}

my ($ns_file, $ns_fn);
if (@ARGV == 0) {
  ($ns_file, $ns_fn) = (\*STDOUT, "stdout");
} else {
  $ns_fn = shift @ARGV;
  open($ns_file, ">", $ns_fn)
    or die("$0: Could not open '$ns_fn' for writing\n");
}

my ($last_reco, $last_begin, $last_end, @nonsil) = ("", 0, 0, ());
foreach my $line (<$ctm_file>) {
  chomp $line;
  my @toks = split(" ", $line);
  unless (@toks == 5 || @toks == 6 ) {
    my $no = $ctm_file->input_line_number();
    die("$0: $ctm_fn line $no: could not parse line\n");
  }
  my ($reco, $channel, $begin, $len, $word) = @toks[0..5];
  next if ($word eq $sil);
  if ($last_reco && ($reco ne $last_reco)) {
    print $ns_file "$last_reco ";
    print $ns_file join(" ; ", @nonsil);
    print $ns_file "\n";
    ($last_begin, $last_end, @nonsil) = (0, 0, ());
  }
  $begin *= $scale;
  my $end = $begin + $len * $scale;
  if (($begin - $last_end) < $frame_shift * $scale) {
    pop @nonsil;
    $begin = $last_begin;
  }
  push(@nonsil, sprintf("$fmt", $begin, $end));
  ($last_reco, $last_begin, $last_end) = ($reco, $begin, $end);
}

if ($last_reco) {
  print $ns_file "$last_reco ";
  print $ns_file join(" ; ", @nonsil);
  print $ns_file "\n"; 
}

__END__

=head1 USAGE

ctm_to_nonsilence.pl [opts] [<ctm-file> [<ns-file>]]
e.g. ctm_to_nonsilence.pl data/tri4b_ali_dev_clean/{ctm,nonsil}

 Options:
  --help                         Short help
  --man                          Long help
  --frame-shift SEC              Frames/sec. Default is 0.01
  --samp-rate N                  Samples/sec. Default is 16000
  --print-as (secs|frames|samps) What to print intervals as. Defaults to secs
  --sil TOKEN                    Silence token (to ignore). Defaults to <eps>

=head1 DESCRIPTION

Converts segments in a CTM file into an archive file, one entry per recording,
which lists the contiguous spans corresponding to non-silence
(i.e non-<eps> CTM segments).

=cut
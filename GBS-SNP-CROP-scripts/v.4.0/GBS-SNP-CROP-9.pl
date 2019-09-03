#!/usr/bin/perl

###########################################################################################################
# GBS-SNP-CROP: GBS SNP Calling Reference Optional Pipeline
#
# Authors: Arthur Melo, Radhika Bartaula, Iago Hale
# Department of Agriculture, Nutrition, and Food Systems, University of New Hampshire, Durham, NH, 03824
#
# A detailed description can be found at https://github.com/halelab/GBS-SNP-CROP
# 
# For help: perl GBS-SNP-CROP-9.pl
###########################################################################################################

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use List::Util qw( min max sum );

######################
# The help function
######################
my $help = $ARGV[0];
my ($GenoMatrix,$output,$MockRef);

my $H = "\n###########################################################\n"
	."GBS-SNP-CROP: GBS SNP Calling Reference Optional Pipeline\n"
	."###########################################################\n"
	."Version: 4.0\n"
	."Step 9: Provide the cluster ID and other descriptors for all called variants. Only for Mock Reference analysis\n"
	."\nA detailed description can be found at https://github.com/halelab/GBS-SNP-CROP\n\n"
	."Usage: perl GBS-SNP-CROP-9.pl [options]\n\n"
	."Options:\n"
	."-in: Final genotyping matrix input file. The output from step 7. File. Default: GSC.GenoMatrix.txt\n"
	."-out: Output label name without extension. String. Default: GSC\n"
	."-ref: Reference FASTA file (the Cluster Mock Reference). File. Required.\n\n";

if (! defined $help or $help =~ "h" or $help =~ "H")  {
	print "$H";
	goto FINAL;
}
#################################
# Setting the parameters values
#################################
$GenoMatrix = 'GSC.GenoMatrix.txt'; $output = 'GSC';

GetOptions(
'in=s' => \$GenoMatrix,		# file
'out=s' => \$output,		# string
'ref=s' => \$MockRef,		# file
) or die "H\n";

#########################
# Starting GBS-SNP-CROP
#########################
print "\n#################################\n# GBS-SNP-CROP, Step 9, v.4.0\n#################################\n";
my $sttime = time;
print "The GBS-SNP-CROP is parsing the Genotyping matrix to provide the Cluster/Centroid ID and others descriptive results from the variants called...\n";

# For each FASTA entry on Mock Ref Cluster, estimate the Cluster length, and both start and end positions.
my $T1 = "Temp1.txt";
open my $Temp1, ">", "$T1" or die "Unable to load $T1 file\n";

my $prev_length = 0;
my $prev_start = 1;
my @len = ();

open my $MR, "<", "$MockRef" or die "Unable to open $MockRef file\n";
{
	local $/ = ">";
	my @file = <$MR>;
	shift @file;
	chomp @file;

	foreach my $line(@file) {
		my ($name, $seq) = split /\n/, $line, 2;
		my $length = ((length $seq) + 19);
		push @len, $length; 
		my $start = $prev_start + $prev_length;
		my $end = $start + ($length - 1);

		$prev_length = $length;
		$prev_start = $start;
		my $x = join ("\t",$name,$length,$start,$end);
		print $Temp1 "$x\n";
	}
}
close $MR;
close $Temp1;

# Open both the genotyping matrix and Temp1 in order to estimate the SNP position on cluster.
open my $VAR, "<", "$GenoMatrix" or die "can't open $GenoMatrix file";
open my $D1, "<", "Temp1.txt" or die "can't open Temp1.txt file";

my $T2 = "Temp2.txt";
open my $Temp2, ">", "$T2" or die "Unable to load $T2 file\n";

my $chr_mr;

my @position_list = ();
while (<$VAR>) {
	chomp;
	my @input1 = split("\t", $_);
	$chr_mr = $input1[0];
	my $pos = $input1[1];
	push @position_list, $pos;
}
close $VAR;

my $i = 0;
my $var_cnt = (scalar @position_list) - 1;

while (<$D1>) {
	chomp;
	my @input2 = split ("\t", $_);
	chomp @input2;
	my $clusterID = $input2[0];
	my $cl_length = $input2[1];
	my $start = $input2[2];
	my $end = $input2[3];

	if ( $position_list[$i] > $end ) {
		next;

	} else {
		my $genome_coord = $position_list[$i];
		my $snp_pos_cluster = ( ($genome_coord - $start) + 1);
		if ($snp_pos_cluster == 0) {
			$snp_pos_cluster = 1
		}
		my $y = join ("\t",$chr_mr, $genome_coord, $clusterID, $start, $end, $cl_length, $snp_pos_cluster);
		print $Temp2 "$y\n";
		$i++;

		if ( $i > $var_cnt ) {
			goto CLOSE;
		}

		if ( $position_list[$i] <= $end ) {
			while ( $position_list[$i] <= $end ) {
				my $next_genome_coord = $position_list[$i];
				my $next_snp_pos_in_cluster = ( ($next_genome_coord - $start) + 1);
				if ($next_snp_pos_in_cluster == 0) {
					$next_snp_pos_in_cluster = 1
				}
				my $y = join ("\t",$chr_mr, $next_genome_coord, $clusterID, $start, $end, $cl_length, $next_snp_pos_in_cluster);
				print $Temp2 "$y\n";
				$i++;
				
				if ( $i > $var_cnt ) {
					goto CLOSE;
				}
			}
		}
	}
}

CLOSE:
close $D1;
close $Temp2;
unlink $T1;

# Parse the SNP-call-pos file, creating a hash to cluster name (key) and SNPs positions on genome (values) in order to estimate 
# the distance between SNPs called in the same cluster.

my $T3 = "Temp3.txt";
open my $Temp3, ">", "$T3" or die "Unable to load $T3 file\n";
open my $D2, "<", "Temp2.txt" or die "can't open Temp2.txt file";

my %ClusterHash;
my %LengthHash;
my @snps = ();
my $cl_pos = "";

while (<$D2>) {
	my @input3 = split ("\t", $_);
	chomp @input3;
	my $pos = $input3[1];
	my $clusterID = $input3[2];
	my $len = $input3[3];
	
	$LengthHash{$clusterID} = $len;
	push @{ $ClusterHash{$clusterID} }, $pos;
}
my @cl_snp_len = values %LengthHash;

for my $clusterID (sort {
	my @aa = $a =~ /^([A-Za-z]+)(\d*)/;
    my @bb = $b =~ /^([A-Za-z]+)(\d*)/;
    lc $aa[0] cmp lc $bb[0] or $aa[1] <=> $bb[1];
	} keys %ClusterHash) {
	$cl_pos = join ("\t",$clusterID, join (",", @{ $ClusterHash{$clusterID} } ) );

	my @snp_pos = split ("\t", $cl_pos);
	my $clID = $snp_pos[0];
	my @pos = split (",", $snp_pos[1]);

	if (scalar @pos == 1) {
		my $snp_cnt = 1;
		my $dist1 = "-";
		my $mn_dist = "-";
		my $mx_dist = "-";
		my $z = join ("\t", $clID, $snp_cnt, $dist1, $mn_dist, $mx_dist);
		print $Temp3 "$z\n";
		next;

	} elsif (scalar @pos > 1) {
		my $snp_cnt = scalar @pos;
		push @snps, $snp_cnt;
		my @dists = ();
		for (my $i=0; $i<=(scalar(@pos) - 2); $i++ ) {
			my $dist = $pos[$i+1] - $pos[$i];
			push @dists, $dist;
		}
		my $mn_dist = min @dists;
		my $mx_dist = sum @dists;
		my $dists = join (",", @dists);
		my $z = join ("\t", $clID, $snp_cnt, $dists, $mn_dist, $mx_dist);
		print $Temp3 "$z\n";
		next;
	}
}
close $D2;
close $Temp3;

# Creating the output file

my $out = join (".","$output","desc","txt");
open my $FinalOUT, ">", "$out" or die "Unable to load $out file\n";

my %FinalHash;

open my $D3, "<", "Temp3.txt" or die "can't open Temp3.txt file";
while (<$D3>) {
	my @input4 = split ("\t", $_);
	chomp @input4;
	$FinalHash{$input4[0]} = join ("\t", $input4[1], $input4[2], $input4[3], $input4[4]);
	
}
close $D3;

open my $D4, "<", "Temp2.txt" or die "can't open Temp2.txt file";
while (my $line = <$D4>) {
	my @input5 = split ("\t", $line);
	chomp @input5;

	if (exists $FinalHash{$input5[2]}) {
		my $FinalLine = join ("\t", $input5[0],$input5[1],$input5[2],$input5[3], $input5[4], $input5[5], $input5[6], $FinalHash{$input5[2]});
		print $FinalOUT "$FinalLine\n";
		next;

	} else {
		next;
	}
}

close $D4;
unlink $T2;
unlink $T3;

print "DONE.\n";
print "\nElapsed time: ", sprintf("%.2f",((time - $sttime)/60)), " min", "\n";
print "Please cite: Melo et al. (2016) GBS-SNP-CROP: A reference-optional pipeline for\n"
."SNP discovery and plant germplasm characterization using variable length, paired-end\n"
."genotyping-by-sequencing data. BMC Bioinformatics. DOI 10.1186/s12859-016-0879-y.\n\n";

FINAL:
exit;

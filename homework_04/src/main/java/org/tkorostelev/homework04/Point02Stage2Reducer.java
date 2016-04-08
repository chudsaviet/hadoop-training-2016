package org.tkorostelev.homework04;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

import java.io.IOException;

public class Point02Stage2Reducer
        extends Reducer<IntWritable, Text, IntWritable, Text> {

    @Override
    public void reduce(IntWritable key, Iterable<Text> values,
                       Context context)
            throws IOException, InterruptedException {

        for (Text value: values) {
            context.write(key, value);
        }

    }
}
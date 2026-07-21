#include <libxml/xmlreader.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *name;
    uint64_t count;
} counter_t;

static counter_t counters[] = {
    {"VariationArchive", 0}, {"ClinicalAssertion", 0}, {"ObservedIn", 0},
    {"Sample", 0}, {"Origin", 0}, {"Species", 0}, {"AffectedStatus", 0},
    {"NumberTested", 0}, {"Age", 0}, {"Gender", 0}, {"Sex", 0},
    {"Ethnicity", 0}, {"GeographicOrigin", 0}, {"Tissue", 0},
    {"FamilyData", 0}, {"Method", 0}, {"MethodType", 0},
    {"TypePlatform", 0}, {"MethodAttribute", 0}, {"ObservedData", 0},
    {"Attribute", 0}, {"MolecularConsequence", 0},
    {"FunctionalConsequence", 0}, {"Co-occurrence", 0},
    {"Sample/Origin", 0}, {"Sample/Species", 0},
    {"Sample/AffectedStatus", 0}, {"Sample/NumberTested", 0},
    {"Sample/Age", 0}, {"Sample/Gender", 0}, {"Sample/Sex", 0},
    {"Sample/Ethnicity", 0}, {"Sample/GeographicOrigin", 0},
    {"Sample/Tissue", 0}, {"Sample/FamilyData", 0},
    {"Method/MethodType", 0}, {"Method/TypePlatform", 0},
    {"Method/MethodAttribute", 0}, {"ObservedData/Attribute", 0},
    {"MolecularConsequence/XRef", 0}, {"FunctionalConsequence/XRef", 0}
};

static void increment(const char *label) {
    size_t i;
    for (i = 0; i < sizeof(counters) / sizeof(counters[0]); i++) {
        if (strcmp(counters[i].name, label) == 0) {
            counters[i].count++;
            return;
        }
    }
}

int main(int argc, char **argv) {
    xmlTextReaderPtr reader;
    int status;
    size_t i;
    int sample_depth = -1;
    int method_depth = -1;
    int observed_data_depth = -1;
    int molecular_depth = -1;
    int functional_depth = -1;
    if (argc != 2) {
        fprintf(stderr, "usage: %s ClinVarVCVRelease.xml[.gz]\n", argv[0]);
        return 2;
    }
    xmlInitParser();
    reader = xmlReaderForFile(argv[1], NULL, XML_PARSE_NONET | XML_PARSE_COMPACT | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    if (!reader) {
        fprintf(stderr, "cannot open XML input: %s\n", argv[1]);
        return 1;
    }
    while ((status = xmlTextReaderRead(reader)) == 1) {
        const xmlChar *name = xmlTextReaderConstLocalName(reader);
        int node_type = xmlTextReaderNodeType(reader);
        int depth = xmlTextReaderDepth(reader);
        if (!name) continue;
        if (node_type == XML_READER_TYPE_END_ELEMENT) {
            if (depth == sample_depth) sample_depth = -1;
            if (depth == method_depth) method_depth = -1;
            if (depth == observed_data_depth) observed_data_depth = -1;
            if (depth == molecular_depth) molecular_depth = -1;
            if (depth == functional_depth) functional_depth = -1;
            continue;
        }
        if (node_type != XML_READER_TYPE_ELEMENT) continue;
        for (i = 0; i < sizeof(counters) / sizeof(counters[0]); i++) {
            if (xmlStrEqual(name, BAD_CAST counters[i].name)) {
                counters[i].count++;
                break;
            }
        }
        if (sample_depth >= 0 && depth > sample_depth) {
            if (xmlStrEqual(name, BAD_CAST "Origin")) increment("Sample/Origin");
            else if (xmlStrEqual(name, BAD_CAST "Species")) increment("Sample/Species");
            else if (xmlStrEqual(name, BAD_CAST "AffectedStatus")) increment("Sample/AffectedStatus");
            else if (xmlStrEqual(name, BAD_CAST "NumberTested")) increment("Sample/NumberTested");
            else if (xmlStrEqual(name, BAD_CAST "Age")) increment("Sample/Age");
            else if (xmlStrEqual(name, BAD_CAST "Gender")) increment("Sample/Gender");
            else if (xmlStrEqual(name, BAD_CAST "Sex")) increment("Sample/Sex");
            else if (xmlStrEqual(name, BAD_CAST "Ethnicity")) increment("Sample/Ethnicity");
            else if (xmlStrEqual(name, BAD_CAST "GeographicOrigin")) increment("Sample/GeographicOrigin");
            else if (xmlStrEqual(name, BAD_CAST "Tissue")) increment("Sample/Tissue");
            else if (xmlStrEqual(name, BAD_CAST "FamilyData")) increment("Sample/FamilyData");
        }
        if (method_depth >= 0 && depth > method_depth) {
            if (xmlStrEqual(name, BAD_CAST "MethodType")) increment("Method/MethodType");
            else if (xmlStrEqual(name, BAD_CAST "TypePlatform")) increment("Method/TypePlatform");
            else if (xmlStrEqual(name, BAD_CAST "MethodAttribute")) increment("Method/MethodAttribute");
        }
        if (observed_data_depth >= 0 && depth > observed_data_depth &&
            xmlStrEqual(name, BAD_CAST "Attribute")) increment("ObservedData/Attribute");
        if (molecular_depth >= 0 && depth > molecular_depth &&
            xmlStrEqual(name, BAD_CAST "XRef")) increment("MolecularConsequence/XRef");
        if (functional_depth >= 0 && depth > functional_depth &&
            xmlStrEqual(name, BAD_CAST "XRef")) increment("FunctionalConsequence/XRef");
        if (xmlStrEqual(name, BAD_CAST "Sample")) sample_depth = depth;
        else if (xmlStrEqual(name, BAD_CAST "Method")) method_depth = depth;
        else if (xmlStrEqual(name, BAD_CAST "ObservedData")) observed_data_depth = depth;
        else if (xmlStrEqual(name, BAD_CAST "MolecularConsequence")) molecular_depth = depth;
        else if (xmlStrEqual(name, BAD_CAST "FunctionalConsequence")) functional_depth = depth;
    }
    if (status < 0) {
        fprintf(stderr, "XML parse error\n");
        xmlFreeTextReader(reader);
        xmlCleanupParser();
        return 1;
    }
    puts("element\tcount");
    for (i = 0; i < sizeof(counters) / sizeof(counters[0]); i++) {
        printf("%s\t%llu\n", counters[i].name, (unsigned long long)counters[i].count);
    }
    xmlFreeTextReader(reader);
    xmlCleanupParser();
    return 0;
}

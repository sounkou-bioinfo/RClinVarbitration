/* RClinVarbitration DuckDB extension
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * libxml2 performs one forward scan of a ClinVar VCV XML/XML.GZ release.
 * The table function emits only ClinVar-domain facts attached to stable public
 * accessions or domain-scoped child identities. XML parser coordinates and
 * generic element/attribute statements are deliberately not exposed.
 */
#include "duckdb_extension.h"

#include <libxml/xmlreader.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

DUCKDB_EXTENSION_EXTERN

#define RCLINVAR_CHUNK_SIZE 1024U
#define RCLINVAR_ERROR_SIZE 512U

typedef struct rclinvar_fact {
    uint64_t record_ordinal;
    uint64_t fact_ordinal;
    char *vcv_accession;
    char *rcv_entity_id;
    char *scv_entity_id;
    char *entity_type;
    char *entity_id;
    char *parent_type;
    char *parent_id;
    char *field;
    char *value;
} rclinvar_fact_t;

typedef struct rclinvar_stack_entry {
    char *name;
    char *semantic_type;
    char *semantic_id;
    char *parent_type;
    char *parent_id;
    char *type_attribute;
    char *id_attribute;
    char *contributes_attribute;
    char *text;
    size_t text_length;
    size_t text_capacity;
} rclinvar_stack_entry_t;

typedef struct rclinvar_bind_state {
    char *path;
} rclinvar_bind_state_t;

typedef struct rclinvar_scan_state {
    xmlTextReaderPtr reader;
    rclinvar_fact_t *facts;
    size_t fact_count;
    size_t fact_capacity;
    size_t fact_pos;
    rclinvar_stack_entry_t *stack;
    size_t stack_count;
    size_t stack_capacity;
    uint64_t record_ordinal;
    uint64_t fact_ordinal;
    uint64_t allele_ordinal;
    uint64_t gene_ordinal;
    uint64_t location_ordinal;
    uint64_t condition_ordinal;
    uint64_t observation_ordinal;
    uint64_t citation_ordinal;
    uint64_t citation_identifier_ordinal;
    uint64_t xref_ordinal;
    uint64_t attribute_ordinal;
    uint64_t name_ordinal;
    uint64_t text_ordinal;
    char *vcv_accession;
    int active_record;
    int finished;
    char error[RCLINVAR_ERROR_SIZE];
} rclinvar_scan_state_t;

static char *rclinvar_strdup(const char *text) {
    size_t n;
    char *out;
    if (!text) return NULL;
    n = strlen(text);
    out = (char *)malloc(n + 1U);
    if (!out) return NULL;
    memcpy(out, text, n + 1U);
    return out;
}

static char *rclinvar_attribute(xmlTextReaderPtr reader, const char *name) {
    xmlChar *value = xmlTextReaderGetAttribute(reader, BAD_CAST name);
    char *out;
    if (!value) return NULL;
    out = rclinvar_strdup((const char *)value);
    xmlFree(value);
    return out;
}

static char *rclinvar_snake(const char *name) {
    size_t i;
    size_t n;
    size_t out_n = 0;
    char *out;
    if (!name) return NULL;
    n = strlen(name);
    out = (char *)malloc(n * 2U + 1U);
    if (!out) return NULL;
    for (i = 0; i < n; i++) {
        unsigned char current = (unsigned char)name[i];
        unsigned char previous = i ? (unsigned char)name[i - 1U] : 0;
        unsigned char next = i + 1U < n ? (unsigned char)name[i + 1U] : 0;
        if (current == '-' || current == ' ' || current == ':') {
            if (out_n && out[out_n - 1U] != '_') out[out_n++] = '_';
        } else if (isupper(current)) {
            if (out_n && out[out_n - 1U] != '_' &&
                (islower(previous) || isdigit(previous) || (isupper(previous) && islower(next)))) {
                out[out_n++] = '_';
            }
            out[out_n++] = (char)tolower(current);
        } else {
            out[out_n++] = (char)tolower(current);
        }
    }
    while (out_n && out[out_n - 1U] == '_') out_n--;
    out[out_n] = '\0';
    return out;
}

static char *rclinvar_scoped_id(const char *parent_id, const char *kind, uint64_t ordinal) {
    int n;
    char *out;
    if (!parent_id || !kind) return NULL;
    n = snprintf(NULL, 0, "%s#%s/%llu", parent_id, kind, (unsigned long long)ordinal);
    if (n < 0) return NULL;
    out = (char *)malloc((size_t)n + 1U);
    if (!out) return NULL;
    snprintf(out, (size_t)n + 1U, "%s#%s/%llu", parent_id, kind, (unsigned long long)ordinal);
    return out;
}

static void rclinvar_set_error(rclinvar_scan_state_t *state, const char *message) {
    if (!state || state->error[0]) return;
    snprintf(state->error, sizeof(state->error), "%s", message ? message : "ClinVar XML parser failed");
}

static int rclinvar_is_whitespace(const char *text) {
    const unsigned char *cursor = (const unsigned char *)text;
    if (!text) return 1;
    while (*cursor) {
        if (!isspace(*cursor)) return 0;
        cursor++;
    }
    return 1;
}

static void rclinvar_fact_clear(rclinvar_fact_t *fact) {
    if (!fact) return;
    free(fact->vcv_accession);
    free(fact->rcv_entity_id);
    free(fact->scv_entity_id);
    free(fact->entity_type);
    free(fact->entity_id);
    free(fact->parent_type);
    free(fact->parent_id);
    free(fact->field);
    free(fact->value);
    memset(fact, 0, sizeof(*fact));
}

static void rclinvar_facts_reset(rclinvar_scan_state_t *state) {
    size_t i;
    if (!state) return;
    for (i = state->fact_pos; i < state->fact_count; i++) rclinvar_fact_clear(&state->facts[i]);
    state->fact_count = 0;
    state->fact_pos = 0;
}

static int rclinvar_facts_reserve(rclinvar_scan_state_t *state, size_t required) {
    size_t capacity;
    rclinvar_fact_t *facts;
    if (required <= state->fact_capacity) return 1;
    capacity = state->fact_capacity ? state->fact_capacity : 32U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U) {
            rclinvar_set_error(state, "ClinVar semantic fact queue is too large");
            return 0;
        }
        capacity *= 2U;
    }
    facts = (rclinvar_fact_t *)realloc(state->facts, capacity * sizeof(*facts));
    if (!facts) {
        rclinvar_set_error(state, "out of memory allocating ClinVar semantic facts");
        return 0;
    }
    memset(facts + state->fact_capacity, 0, (capacity - state->fact_capacity) * sizeof(*facts));
    state->facts = facts;
    state->fact_capacity = capacity;
    return 1;
}

static rclinvar_stack_entry_t *rclinvar_nearest_type(rclinvar_scan_state_t *state,
                                                       const char *semantic_type);

static int rclinvar_emit(rclinvar_scan_state_t *state, const char *entity_type, const char *entity_id,
                         const char *parent_type, const char *parent_id, const char *field,
                         const char *value) {
    rclinvar_fact_t *fact;
    if (!state || !entity_type || !entity_id || !field || !value) return 0;
    if (!rclinvar_facts_reserve(state, state->fact_count + 1U)) return 0;
    fact = &state->facts[state->fact_count];
    fact->record_ordinal = state->record_ordinal;
    fact->fact_ordinal = ++state->fact_ordinal;
    {
        rclinvar_stack_entry_t *rcv = rclinvar_nearest_type(state, "rcv_assertion");
        rclinvar_stack_entry_t *scv = rclinvar_nearest_type(state, "scv_assertion");
        fact->vcv_accession = rclinvar_strdup(state->vcv_accession ? state->vcv_accession : "");
        fact->rcv_entity_id = strcmp(entity_type, "rcv_assertion") == 0 ? rclinvar_strdup(entity_id) :
                              (rcv ? rclinvar_strdup(rcv->semantic_id) : NULL);
        fact->scv_entity_id = strcmp(entity_type, "scv_assertion") == 0 ? rclinvar_strdup(entity_id) :
                              (scv ? rclinvar_strdup(scv->semantic_id) : NULL);
    }
    fact->entity_type = rclinvar_strdup(entity_type);
    fact->entity_id = rclinvar_strdup(entity_id);
    fact->parent_type = parent_type ? rclinvar_strdup(parent_type) : NULL;
    fact->parent_id = parent_id ? rclinvar_strdup(parent_id) : NULL;
    fact->field = rclinvar_strdup(field);
    fact->value = rclinvar_strdup(value);
    if (!fact->vcv_accession || !fact->entity_type || !fact->entity_id || !fact->field || !fact->value ||
        (parent_type && !fact->parent_type) || (parent_id && !fact->parent_id)) {
        rclinvar_fact_clear(fact);
        rclinvar_set_error(state, "out of memory copying ClinVar semantic fact");
        return 0;
    }
    state->fact_count++;
    return 1;
}

static void rclinvar_stack_entry_clear(rclinvar_stack_entry_t *entry) {
    if (!entry) return;
    free(entry->name);
    free(entry->semantic_type);
    free(entry->semantic_id);
    free(entry->parent_type);
    free(entry->parent_id);
    free(entry->type_attribute);
    free(entry->id_attribute);
    free(entry->contributes_attribute);
    free(entry->text);
    memset(entry, 0, sizeof(*entry));
}

static int rclinvar_stack_reserve(rclinvar_scan_state_t *state, size_t required) {
    size_t capacity;
    rclinvar_stack_entry_t *stack;
    if (required <= state->stack_capacity) return 1;
    capacity = state->stack_capacity ? state->stack_capacity : 32U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U) {
            rclinvar_set_error(state, "ClinVar XML nesting is too deep");
            return 0;
        }
        capacity *= 2U;
    }
    stack = (rclinvar_stack_entry_t *)realloc(state->stack, capacity * sizeof(*stack));
    if (!stack) {
        rclinvar_set_error(state, "out of memory allocating ClinVar XML stack");
        return 0;
    }
    memset(stack + state->stack_capacity, 0, (capacity - state->stack_capacity) * sizeof(*stack));
    state->stack = stack;
    state->stack_capacity = capacity;
    return 1;
}

static rclinvar_stack_entry_t *rclinvar_nearest_semantic(rclinvar_scan_state_t *state) {
    size_t i = state ? state->stack_count : 0;
    while (i) {
        rclinvar_stack_entry_t *entry = &state->stack[--i];
        if (entry->semantic_type && entry->semantic_id) return entry;
    }
    return NULL;
}

static rclinvar_stack_entry_t *rclinvar_nearest_type(rclinvar_scan_state_t *state, const char *semantic_type) {
    size_t i = state ? state->stack_count : 0;
    while (i) {
        rclinvar_stack_entry_t *entry = &state->stack[--i];
        if (entry->semantic_type && strcmp(entry->semantic_type, semantic_type) == 0) return entry;
    }
    return NULL;
}

static rclinvar_stack_entry_t *rclinvar_nearest_named(rclinvar_scan_state_t *state, const char *name) {
    size_t i = state ? state->stack_count : 0;
    while (i) {
        rclinvar_stack_entry_t *entry = &state->stack[--i];
        if (entry->name && strcmp(entry->name, name) == 0) return entry;
    }
    return NULL;
}

static int rclinvar_stack_contains(rclinvar_scan_state_t *state, const char *name) {
    return rclinvar_nearest_named(state, name) != NULL;
}

static int rclinvar_append_text(rclinvar_scan_state_t *state, const char *value) {
    rclinvar_stack_entry_t *entry;
    size_t n;
    size_t required;
    size_t capacity;
    char *text;
    if (!state || !state->stack_count || !value) return 1;
    entry = &state->stack[state->stack_count - 1U];
    n = strlen(value);
    if (!n) return 1;
    required = entry->text_length + n + 1U;
    if (required > entry->text_capacity) {
        capacity = entry->text_capacity ? entry->text_capacity : 64U;
        while (capacity < required) {
            if (capacity > SIZE_MAX / 2U) {
                rclinvar_set_error(state, "ClinVar XML text is too large");
                return 0;
            }
            capacity *= 2U;
        }
        text = (char *)realloc(entry->text, capacity);
        if (!text) {
            rclinvar_set_error(state, "out of memory buffering ClinVar XML text");
            return 0;
        }
        entry->text = text;
        entry->text_capacity = capacity;
    }
    memcpy(entry->text + entry->text_length, value, n);
    entry->text_length += n;
    entry->text[entry->text_length] = '\0';
    return 1;
}

static int rclinvar_emit_entry(rclinvar_scan_state_t *state, const rclinvar_stack_entry_t *entry,
                               const char *field, const char *value) {
    return rclinvar_emit(state, entry->semantic_type, entry->semantic_id,
                         entry->parent_type, entry->parent_id, field, value);
}

static int rclinvar_emit_reader_attributes(rclinvar_scan_state_t *state, xmlTextReaderPtr reader,
                                           const rclinvar_stack_entry_t *entry) {
    int status = xmlTextReaderMoveToFirstAttribute(reader);
    while (status == 1) {
        const xmlChar *name = xmlTextReaderConstLocalName(reader);
        const xmlChar *value = xmlTextReaderConstValue(reader);
        char *field = rclinvar_snake((const char *)name);
        if (!field || !rclinvar_emit_entry(state, entry, field, value ? (const char *)value : "")) {
            free(field);
            return 0;
        }
        free(field);
        status = xmlTextReaderMoveToNextAttribute(reader);
    }
    xmlTextReaderMoveToElement(reader);
    if (status < 0) {
        rclinvar_set_error(state, "failed reading ClinVar XML attributes");
        return 0;
    }
    return 1;
}

static int rclinvar_emit_attribute_if_present(rclinvar_scan_state_t *state, xmlTextReaderPtr reader,
                                              const rclinvar_stack_entry_t *entry,
                                              const char *xml_name, const char *field) {
    char *value = rclinvar_attribute(reader, xml_name);
    int ok = 1;
    if (value) ok = rclinvar_emit_entry(state, entry, field, value);
    free(value);
    return ok;
}

static int rclinvar_transfer_attributes(rclinvar_scan_state_t *state, xmlTextReaderPtr reader,
                                        const char *local_name,
                                        const rclinvar_stack_entry_t *context) {
    if (!context) return 1;
    if (strcmp(local_name, "ClinVarAccession") == 0 && strcmp(context->semantic_type, "scv_assertion") == 0) {
        return rclinvar_emit_attribute_if_present(state, reader, context, "Accession", "scv_accession") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "Version", "scv_version") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "DateCreated", "accession_date_created") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "DateUpdated", "accession_date_updated") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "SubmitterName", "submitter_name") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "OrgID", "submitter_id") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "OrganizationCategory", "organization_category") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "OrgAbbreviation", "organization_abbreviation");
    }
    if (strcmp(local_name, "ClinVarSubmissionID") == 0 && strcmp(context->semantic_type, "scv_assertion") == 0) {
        return rclinvar_emit_attribute_if_present(state, reader, context, "localKey", "local_key") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "submittedAssembly", "submitted_assembly") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "title", "submission_title");
    }
    if (strcmp(local_name, "Classification") == 0 && strcmp(context->semantic_type, "scv_assertion") == 0) {
        return rclinvar_emit_attribute_if_present(state, reader, context, "DateLastEvaluated", "date_last_evaluated");
    }
    if (strcmp(local_name, "GermlineClassification") == 0 ||
        strcmp(local_name, "SomaticClinicalImpact") == 0 ||
        strcmp(local_name, "OncogenicityClassification") == 0) {
        return rclinvar_emit_attribute_if_present(state, reader, context, "DateLastEvaluated", "date_last_evaluated") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "NumberOfSubmissions", "number_of_submissions") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "NumberOfSubmitters", "number_of_submitters") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "DateCreated", "classification_date_created") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "MostRecentSubmission", "most_recent_submission");
    }
    if (strcmp(local_name, "Description") == 0 && rclinvar_stack_contains(state, "GermlineClassification")) {
        return rclinvar_emit_attribute_if_present(state, reader, context, "DateLastEvaluated", "date_last_evaluated") &&
               rclinvar_emit_attribute_if_present(state, reader, context, "SubmissionCount", "submission_count");
    }
    return 1;
}

static int rclinvar_semantic_start(rclinvar_scan_state_t *state, xmlTextReaderPtr reader,
                                   const char *local_name, rclinvar_stack_entry_t *entry,
                                   rclinvar_stack_entry_t *parent) {
    char *identifier = NULL;
    const char *scope = parent ? parent->semantic_id : state->vcv_accession;
    uint64_t ordinal = 0;

    if (strcmp(local_name, "VariationArchive") == 0) {
        entry->semantic_type = rclinvar_strdup("variation");
        entry->semantic_id = rclinvar_strdup(state->vcv_accession);
    } else if ((strcmp(local_name, "SimpleAllele") == 0 || strcmp(local_name, "Haplotype") == 0 ||
                strcmp(local_name, "Genotype") == 0) && parent &&
               (strcmp(parent->semantic_type, "variation") == 0 || strcmp(parent->semantic_type, "allele") == 0) &&
               !rclinvar_stack_contains(state, "ClinicalAssertion")) {
        entry->semantic_type = rclinvar_strdup("allele");
        identifier = rclinvar_attribute(reader, "AlleleID");
        ordinal = ++state->allele_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, identifier ? identifier : "allele", ordinal);
    } else if (strcmp(local_name, "Gene") == 0 && parent && strcmp(parent->semantic_type, "allele") == 0) {
        entry->semantic_type = rclinvar_strdup("gene");
        identifier = rclinvar_attribute(reader, "GeneID");
        ordinal = ++state->gene_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, identifier ? identifier : "gene", ordinal);
    } else if (strcmp(local_name, "SequenceLocation") == 0 && parent && strcmp(parent->semantic_type, "allele") == 0) {
        entry->semantic_type = rclinvar_strdup("location");
        ordinal = ++state->location_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "location", ordinal);
    } else if (strcmp(local_name, "RCVAccession") == 0) {
        entry->semantic_type = rclinvar_strdup("rcv_assertion");
        entry->semantic_id = rclinvar_attribute(reader, "Accession");
    } else if (strcmp(local_name, "ClinicalAssertion") == 0) {
        entry->semantic_type = rclinvar_strdup("scv_assertion");
        identifier = rclinvar_attribute(reader, "ID");
        entry->semantic_id = rclinvar_scoped_id(state->vcv_accession, "assertion", identifier ? strtoull(identifier, NULL, 10) : state->fact_ordinal + 1U);
    } else if ((strcmp(local_name, "ClassifiedCondition") == 0 && parent && strcmp(parent->semantic_type, "rcv_assertion") == 0) ||
               (strcmp(local_name, "Trait") == 0 && parent &&
                (strcmp(parent->semantic_type, "variation") == 0 || strcmp(parent->semantic_type, "scv_assertion") == 0))) {
        entry->semantic_type = rclinvar_strdup("condition");
        ordinal = ++state->condition_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "condition", ordinal);
    } else if (strcmp(local_name, "ObservedIn") == 0 && parent && strcmp(parent->semantic_type, "scv_assertion") == 0) {
        entry->semantic_type = rclinvar_strdup("observation");
        ordinal = ++state->observation_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "observation", ordinal);
    } else if (strcmp(local_name, "Citation") == 0 && parent) {
        entry->semantic_type = rclinvar_strdup("citation");
        ordinal = ++state->citation_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "citation", ordinal);
    } else if (strcmp(local_name, "ID") == 0 && parent && strcmp(parent->semantic_type, "citation") == 0) {
        entry->semantic_type = rclinvar_strdup("citation_identifier");
        ordinal = ++state->citation_identifier_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "identifier", ordinal);
    } else if (strcmp(local_name, "XRef") == 0 && parent &&
               (strcmp(parent->semantic_type, "condition") == 0 || strcmp(parent->semantic_type, "allele") == 0)) {
        entry->semantic_type = rclinvar_strdup("xref");
        ordinal = ++state->xref_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "xref", ordinal);
    } else if (strcmp(local_name, "Attribute") == 0 && parent) {
        entry->semantic_type = rclinvar_strdup("attribute");
        ordinal = ++state->attribute_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "attribute", ordinal);
    } else if (strcmp(local_name, "ElementValue") == 0 && parent &&
               strcmp(parent->semantic_type, "condition") == 0 && rclinvar_stack_contains(state, "Name")) {
        entry->semantic_type = rclinvar_strdup("condition_name");
        ordinal = ++state->name_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "name", ordinal);
    } else if ((strcmp(local_name, "Comment") == 0 || strcmp(local_name, "CitationText") == 0) && parent) {
        entry->semantic_type = rclinvar_strdup("text");
        ordinal = ++state->text_ordinal;
        entry->semantic_id = rclinvar_scoped_id(scope, "text", ordinal);
    }
    free(identifier);

    if ((entry->semantic_type && !entry->semantic_id) || (!entry->semantic_type && entry->semantic_id)) {
        rclinvar_set_error(state, "out of memory naming ClinVar semantic entity");
        return 0;
    }
    if (entry->semantic_type && parent) {
        entry->parent_type = rclinvar_strdup(parent->semantic_type);
        entry->parent_id = rclinvar_strdup(parent->semantic_id);
        if (!entry->parent_type || !entry->parent_id) {
            rclinvar_set_error(state, "out of memory naming ClinVar semantic relation");
            return 0;
        }
    }
    if (entry->semantic_type) {
        if (!rclinvar_emit_entry(state, entry, "_present", "true") ||
            !rclinvar_emit_reader_attributes(state, reader, entry)) return 0;
        if (strcmp(entry->semantic_type, "text") == 0) {
            const char *section = strcmp(local_name, "Comment") == 0 ? "comment" : "citation_text";
            if (!rclinvar_emit_entry(state, entry, "section", section)) return 0;
        }
        if (strcmp(entry->semantic_type, "condition") == 0) {
            rclinvar_stack_entry_t *trait_set = rclinvar_nearest_named(state, "TraitSet");
            rclinvar_stack_entry_t *condition_list = rclinvar_nearest_named(state, "ClassifiedConditionList");
            rclinvar_stack_entry_t *source = trait_set ? trait_set : condition_list;
            if (source) {
                if (source->id_attribute && !rclinvar_emit_entry(state, entry, "trait_set_id", source->id_attribute)) return 0;
                if (source->type_attribute && !rclinvar_emit_entry(state, entry, "trait_set_type", source->type_attribute)) return 0;
                if (source->contributes_attribute &&
                    !rclinvar_emit_entry(state, entry, "contributes_to_aggregate_classification", source->contributes_attribute)) return 0;
            }
        }
    }
    return 1;
}

static int rclinvar_start_element(rclinvar_scan_state_t *state, xmlTextReaderPtr reader,
                                  const char *local_name) {
    rclinvar_stack_entry_t *entry;
    rclinvar_stack_entry_t *parent;
    int empty;
    if (!rclinvar_stack_reserve(state, state->stack_count + 1U)) return 0;
    parent = rclinvar_nearest_semantic(state);
    entry = &state->stack[state->stack_count];
    memset(entry, 0, sizeof(*entry));
    entry->name = rclinvar_strdup(local_name);
    entry->type_attribute = rclinvar_attribute(reader, "Type");
    entry->id_attribute = rclinvar_attribute(reader, "ID");
    entry->contributes_attribute = rclinvar_attribute(reader, "ContributesToAggregateClassification");
    if (!entry->name) {
        rclinvar_set_error(state, "out of memory copying ClinVar XML element name");
        return 0;
    }
    if (!rclinvar_semantic_start(state, reader, local_name, entry, parent)) {
        rclinvar_stack_entry_clear(entry);
        return 0;
    }
    state->stack_count++;
    if (!entry->semantic_type && !rclinvar_transfer_attributes(state, reader, local_name, parent)) return 0;
    empty = xmlTextReaderIsEmptyElement(reader);
    if (empty) {
        rclinvar_stack_entry_clear(entry);
        state->stack_count--;
    }
    return 1;
}

static int rclinvar_emit_element_text(rclinvar_scan_state_t *state, rclinvar_stack_entry_t *entry) {
    rclinvar_stack_entry_t *context;
    const char *field = NULL;
    if (!entry->text || rclinvar_is_whitespace(entry->text)) return 1;
    if (entry->semantic_type) {
        if (strcmp(entry->semantic_type, "text") == 0 || strcmp(entry->semantic_type, "attribute") == 0 ||
            strcmp(entry->semantic_type, "condition_name") == 0) field = "value";
        else if (strcmp(entry->semantic_type, "citation_identifier") == 0) field = "identifier";
        else if (strcmp(entry->semantic_type, "condition") == 0 && strcmp(entry->name, "ClassifiedCondition") == 0)
            field = "preferred_name";
        if (field) return rclinvar_emit_entry(state, entry, field, entry->text);
    }
    context = rclinvar_nearest_semantic(state);
    if (!context) return 1;
    if (strcmp(entry->name, "RecordStatus") == 0) field = "record_status";
    else if (strcmp(entry->name, "Species") == 0) field = "species";
    else if (strcmp(entry->name, "CanonicalSPDI") == 0) field = "canonical_spdi";
    else if (strcmp(entry->name, "VariantType") == 0) field = "variant_type";
    else if (strcmp(entry->name, "ReviewStatus") == 0) field = "review_status";
    else if (strcmp(entry->name, "Assertion") == 0) field = "assertion_type";
    else if (strcmp(entry->name, "Origin") == 0) field = "origin";
    else if (strcmp(entry->name, "AffectedStatus") == 0) field = "affected_status";
    else if (strcmp(entry->name, "NumberTested") == 0) field = "number_tested";
    else if (strcmp(entry->name, "MethodType") == 0) field = "method_type";
    else if (strcmp(entry->name, "URL") == 0 && strcmp(context->semantic_type, "citation") == 0) field = "url";
    else if ((strcmp(entry->name, "GermlineClassification") == 0 ||
              strcmp(entry->name, "SomaticClinicalImpact") == 0 ||
              strcmp(entry->name, "OncogenicityClassification") == 0 ||
              (strcmp(entry->name, "Description") == 0 && rclinvar_stack_contains(state, "GermlineClassification"))))
        field = "classification";
    else if (strcmp(entry->name, "Name") == 0 && strcmp(context->semantic_type, "allele") == 0)
        field = "name";
    if (!field) return 1;
    return rclinvar_emit_entry(state, context, field, entry->text);
}

static int rclinvar_end_element(rclinvar_scan_state_t *state, const char *local_name) {
    rclinvar_stack_entry_t *entry;
    int ending_record;
    if (!state->stack_count) return 1;
    entry = &state->stack[state->stack_count - 1U];
    ending_record = strcmp(local_name, "VariationArchive") == 0;
    if (!rclinvar_emit_element_text(state, entry)) return 0;
    rclinvar_stack_entry_clear(entry);
    state->stack_count--;
    if (ending_record) {
        state->active_record = 0;
        free(state->vcv_accession);
        state->vcv_accession = NULL;
    }
    return 1;
}

static int rclinvar_start_record(rclinvar_scan_state_t *state, xmlTextReaderPtr reader) {
    state->record_ordinal++;
    state->fact_ordinal = 0;
    state->allele_ordinal = 0;
    state->gene_ordinal = 0;
    state->location_ordinal = 0;
    state->condition_ordinal = 0;
    state->observation_ordinal = 0;
    state->citation_ordinal = 0;
    state->citation_identifier_ordinal = 0;
    state->xref_ordinal = 0;
    state->attribute_ordinal = 0;
    state->name_ordinal = 0;
    state->text_ordinal = 0;
    free(state->vcv_accession);
    state->vcv_accession = rclinvar_attribute(reader, "Accession");
    if (!state->vcv_accession || !state->vcv_accession[0]) {
        rclinvar_set_error(state, "VariationArchive is missing its ClinVar VCV Accession");
        return 0;
    }
    state->active_record = 1;
    return rclinvar_start_element(state, reader, "VariationArchive");
}

/* Reads until at least one fact is queued, EOF, or an error. */
static int rclinvar_scan_next(rclinvar_scan_state_t *state) {
    int rc;
    while (!state->finished && state->fact_pos == state->fact_count) {
        int node_type;
        const xmlChar *local;
        const xmlChar *value;
        rclinvar_facts_reset(state);
        rc = xmlTextReaderRead(state->reader);
        if (rc == 0) {
            state->finished = 1;
            return 0;
        }
        if (rc < 0) {
            const xmlError *error = xmlGetLastError();
            snprintf(state->error, sizeof(state->error), "ClinVar XML parse error%s%s",
                     error && error->message ? ": " : "", error && error->message ? error->message : "");
            return -1;
        }
        node_type = xmlTextReaderNodeType(state->reader);
        local = xmlTextReaderConstLocalName(state->reader);
        if (node_type == XML_READER_TYPE_ELEMENT) {
            if (!state->active_record) {
                if (local && xmlStrEqual(local, BAD_CAST "VariationArchive")) {
                    if (!rclinvar_start_record(state, state->reader)) return -1;
                }
            } else if (!rclinvar_start_element(state, state->reader, (const char *)local)) {
                return -1;
            }
        } else if (state->active_record && node_type == XML_READER_TYPE_END_ELEMENT) {
            if (!rclinvar_end_element(state, (const char *)local)) return -1;
        } else if (state->active_record &&
                   (node_type == XML_READER_TYPE_TEXT || node_type == XML_READER_TYPE_CDATA)) {
            value = xmlTextReaderConstValue(state->reader);
            if (value && !rclinvar_append_text(state, (const char *)value)) return -1;
        } else if (state->active_record && node_type == XML_READER_TYPE_COMMENT) {
            rclinvar_stack_entry_t *context = rclinvar_nearest_semantic(state);
            value = xmlTextReaderConstValue(state->reader);
            if (context && value && !rclinvar_is_whitespace((const char *)value)) {
                char *id = rclinvar_scoped_id(context->semantic_id, "text", ++state->text_ordinal);
                if (!id || !rclinvar_emit(state, "text", id, context->semantic_type,
                                          context->semantic_id, "section", "xml_comment") ||
                    !rclinvar_emit(state, "text", id, context->semantic_type,
                                   context->semantic_id, "value", (const char *)value)) {
                    free(id);
                    return -1;
                }
                free(id);
            }
        }
    }
    return state->fact_pos < state->fact_count ? 1 : 0;
}

static void rclinvar_bind_destroy(void *pointer) {
    rclinvar_bind_state_t *state = (rclinvar_bind_state_t *)pointer;
    if (!state) return;
    free(state->path);
    free(state);
}

static void rclinvar_scan_destroy(void *pointer) {
    size_t i;
    rclinvar_scan_state_t *state = (rclinvar_scan_state_t *)pointer;
    if (!state) return;
    if (state->reader) xmlFreeTextReader(state->reader);
    for (i = 0; i < state->fact_count; i++) rclinvar_fact_clear(&state->facts[i]);
    free(state->facts);
    for (i = 0; i < state->stack_count; i++) rclinvar_stack_entry_clear(&state->stack[i]);
    free(state->stack);
    free(state->vcv_accession);
    free(state);
}

static void rclinvar_add_column(duckdb_bind_info info, const char *name, duckdb_type type_id) {
    duckdb_logical_type type = duckdb_create_logical_type(type_id);
    duckdb_bind_add_result_column(info, name, type);
    duckdb_destroy_logical_type(&type);
}

static void rclinvar_xml_bind(duckdb_bind_info info) {
    duckdb_value value = NULL;
    char *path = NULL;
    rclinvar_bind_state_t *state = NULL;
    if (duckdb_bind_get_parameter_count(info) != 1U) {
        duckdb_bind_set_error(info, "clinvar_xml_facts() requires exactly one XML or XML.GZ path");
        return;
    }
    value = duckdb_bind_get_parameter(info, 0);
    path = value ? duckdb_get_varchar(value) : NULL;
    if (value) duckdb_destroy_value(&value);
    if (!path || !path[0]) {
        if (path) duckdb_free(path);
        duckdb_bind_set_error(info, "clinvar_xml_facts() path must be a non-empty string");
        return;
    }
    state = (rclinvar_bind_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_free(path);
        duckdb_bind_set_error(info, "out of memory binding clinvar_xml_facts()");
        return;
    }
    state->path = rclinvar_strdup(path);
    duckdb_free(path);
    if (!state->path) {
        rclinvar_bind_destroy(state);
        duckdb_bind_set_error(info, "out of memory copying ClinVar XML path");
        return;
    }
    rclinvar_add_column(info, "record_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "fact_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "vcv_accession", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "rcv_entity_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "scv_entity_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "entity_type", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "entity_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "parent_type", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "parent_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "field", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "value", DUCKDB_TYPE_VARCHAR);
    duckdb_bind_set_bind_data(info, state, rclinvar_bind_destroy);
}

static void rclinvar_xml_init(duckdb_init_info info) {
    const rclinvar_bind_state_t *bind = (const rclinvar_bind_state_t *)duckdb_init_get_bind_data(info);
    rclinvar_scan_state_t *state;
    if (!bind || !bind->path) {
        duckdb_init_set_error(info, "clinvar_xml_facts() bind state is missing");
        return;
    }
    state = (rclinvar_scan_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_init_set_error(info, "out of memory initializing ClinVar XML scan");
        return;
    }
    state->reader = xmlReaderForFile(bind->path, NULL, XML_PARSE_NONET | XML_PARSE_COMPACT | XML_PARSE_NOENT);
    if (!state->reader) {
        rclinvar_scan_destroy(state);
        duckdb_init_set_error(info, "failed to open or parse ClinVar XML/XML.GZ input");
        return;
    }
    duckdb_init_set_max_threads(info, 1);
    duckdb_init_set_init_data(info, state, rclinvar_scan_destroy);
}

static void rclinvar_set_null(duckdb_vector vector, idx_t row) {
    uint64_t *validity;
    duckdb_vector_ensure_validity_writable(vector);
    validity = duckdb_vector_get_validity(vector);
    duckdb_validity_set_row_invalid(validity, row);
}

static void rclinvar_assign_fact(duckdb_data_chunk output, idx_t row, rclinvar_fact_t *fact) {
    uint64_t *record = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 0));
    uint64_t *ordinal = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 1));
    duckdb_vector vcv = duckdb_data_chunk_get_vector(output, 2);
    duckdb_vector rcv = duckdb_data_chunk_get_vector(output, 3);
    duckdb_vector scv = duckdb_data_chunk_get_vector(output, 4);
    duckdb_vector entity_type = duckdb_data_chunk_get_vector(output, 5);
    duckdb_vector entity_id = duckdb_data_chunk_get_vector(output, 6);
    duckdb_vector parent_type = duckdb_data_chunk_get_vector(output, 7);
    duckdb_vector parent_id = duckdb_data_chunk_get_vector(output, 8);
    duckdb_vector field = duckdb_data_chunk_get_vector(output, 9);
    duckdb_vector value = duckdb_data_chunk_get_vector(output, 10);
    record[row] = fact->record_ordinal;
    ordinal[row] = fact->fact_ordinal;
    duckdb_vector_assign_string_element(vcv, row, fact->vcv_accession);
    if (fact->rcv_entity_id) duckdb_vector_assign_string_element(rcv, row, fact->rcv_entity_id);
    else rclinvar_set_null(rcv, row);
    if (fact->scv_entity_id) duckdb_vector_assign_string_element(scv, row, fact->scv_entity_id);
    else rclinvar_set_null(scv, row);
    duckdb_vector_assign_string_element(entity_type, row, fact->entity_type);
    duckdb_vector_assign_string_element(entity_id, row, fact->entity_id);
    if (fact->parent_type) duckdb_vector_assign_string_element(parent_type, row, fact->parent_type);
    else rclinvar_set_null(parent_type, row);
    if (fact->parent_id) duckdb_vector_assign_string_element(parent_id, row, fact->parent_id);
    else rclinvar_set_null(parent_id, row);
    duckdb_vector_assign_string_element(field, row, fact->field);
    duckdb_vector_assign_string_element(value, row, fact->value);
}

static void rclinvar_xml_function(duckdb_function_info info, duckdb_data_chunk output) {
    rclinvar_scan_state_t *state = (rclinvar_scan_state_t *)duckdb_function_get_init_data(info);
    idx_t count = 0;
    if (!state) {
        duckdb_function_set_error(info, "clinvar_xml_facts() scan state is missing");
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    while (count < RCLINVAR_CHUNK_SIZE) {
        rclinvar_fact_t fact;
        int status;
        if (state->fact_pos >= state->fact_count) {
            status = rclinvar_scan_next(state);
            if (status < 0) {
                duckdb_function_set_error(info, state->error[0] ? state->error : "ClinVar XML scan failed");
                duckdb_data_chunk_set_size(output, 0);
                return;
            }
            if (status == 0) break;
        }
        fact = state->facts[state->fact_pos];
        memset(&state->facts[state->fact_pos], 0, sizeof(fact));
        state->fact_pos++;
        rclinvar_assign_fact(output, count, &fact);
        rclinvar_fact_clear(&fact);
        count++;
    }
    duckdb_data_chunk_set_size(output, count);
}

static bool rclinvar_register_xml_facts(duckdb_connection connection) {
    duckdb_table_function function = duckdb_create_table_function();
    duckdb_logical_type parameter_type;
    duckdb_state status;
    if (!function) return false;
    parameter_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    if (!parameter_type) {
        duckdb_destroy_table_function(&function);
        return false;
    }
    duckdb_table_function_set_name(function, "clinvar_xml_facts");
    duckdb_table_function_add_parameter(function, parameter_type);
    duckdb_destroy_logical_type(&parameter_type);
    duckdb_table_function_set_bind(function, rclinvar_xml_bind);
    duckdb_table_function_set_init(function, rclinvar_xml_init);
    duckdb_table_function_set_function(function, rclinvar_xml_function);
    status = duckdb_register_table_function(connection, function);
    duckdb_destroy_table_function(&function);
    return status == DuckDBSuccess;
}

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection connection,
                            duckdb_extension_info info,
                            struct duckdb_extension_access *access) {
    xmlInitParser();
    if (!rclinvar_register_xml_facts(connection)) {
        access->set_error(info, "failed to register clinvar_xml_facts()");
        return false;
    }
    return true;
}

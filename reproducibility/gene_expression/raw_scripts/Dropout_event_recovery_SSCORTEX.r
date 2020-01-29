utilities_path = "/home/yuanhao/single_cell/scripts/evaluation_pipeline/evaluation/utilities.r"
source(utilities_path)
min_expressed_cell = 10
min_expressed_cell_average_expression = 1
ds_mode = 0.5
method_names = c("DISC", "SAVER", "scImpute", "VIPER", "MAGIC", "DCA", "deepImpute", "scScope", "scVI")
### Load raw data and downsampling
raw_data = readh5_loom("/home/yuanhao/github_repositories/DISC/reproducibility/data/SSCORTEX/raw.loom")
compare_gene = rownames(raw_data)
cell_number = ncol(raw_data)
data_list = list(Raw = raw_data)
rm(raw_data)
ds_dir = "/home/yuanhao/data/fn/sscortex/filt_gene_500_5000/merge/ds"
dir.create(ds_dir, showWarnings = F, recursive = T)
output_dir = paste0("/home/yuanhao/data/fn/sscortex/filt_gene_500_5000/merge/ds/ds_", ds_mode, "_results")
dir.create(output_dir, showWarnings = F, recursive = T)
repeats = paste0("downsampling_first_repeat_", seq(5))
observed_file = paste0("L1_Cortex2_filt_ls_merged_s1_s2_unique_rename_ds_", ds_mode, ".loom")
observed_name = paste(delete_last_element(unlist(strsplit(observed_file, ".", fixed = T))), collapse = ".")
data_list[["Observed"]] = list()
for(ii in repeats){
  observed_path = paste(ds_dir, ii, observed_file, sep = "/")
  if(!file.exists(observed_path)){
    cat("Generate ", observed_path, " ...")
    data_list[["Observed"]][[ii]] = downsampling_cell(ds_mode, raw_data)
    save_h5(observed_path, t(data_list[["Observed"]][[ii]]))
  }else{
    data_list[["Observed"]][[ii]] = readh5_loom(observed_path)
  }
  expressed_cell = rowSums(data_list[["Observed"]][[ii]] > 0)
  gene_expression = rowSums(data_list[["Observed"]][[ii]])
  gene_filter = expressed_cell >= min_expressed_cell & gene_expression > expressed_cell * min_expressed_cell_average_expression
  this_used_genes = rownames(data_list[["Observed"]][[ii]])[gene_filter]
  compare_gene = intersect(compare_gene, this_used_genes)
}
gene_number = length(compare_gene)
cat("Use ", gene_number, " genes for comparison.\n")
data_list[["Raw"]] = data_list[["Raw"]][compare_gene, ]
for(ii in method_names){
  data_list[[ii]] = list()
}
for(ii in repeats){
  data_list[["Observed"]][[ii]] = data_list[["Observed"]][[ii]][compare_gene, ]
  ### Load downsampling data and imputation results
  data_list[["DISC"]][[ii]] = readh5_imputation(get_optimal_point33(paste(ds_dir, ii, paste0("DeSCI_2.7.4.33/ds_", ds_mode, "/log.txt"), sep = "/")), with_outliers = T)[compare_gene, ]
  print(dim(data_list[["DISC"]][[ii]]))
  for(jj in setdiff(method_names, "DISC")){
    if(jj == "VIPER"){
      tmp_name = "VIPER_gene"
    }else{
      tmp_name = jj
    }
    data_list[[jj]][[ii]] = readh5_imputation(paste0(paste(ds_dir, ii, "imputation", paste(observed_name, tmp_name, "mc", min_expressed_cell, "mce", min_expressed_cell_average_expression, sep = "_"), sep = "/"), ".hdf5"))[compare_gene, ]
    print(dim(data_list[[jj]][[ii]]))
  }
}
### Settings
method_names = setdiff(names(data_list), "Raw")
method_color = c("gray80", "#FF0000", "#000080", "#BFBF00", "#408000", "#804000", "#00FF00", "#FF8000", "#FF00FF", "#00FFFF")
names(method_color) = method_names
text_color = rep("black", length(method_names))
names(text_color) = method_names
text_color["DISC"] = "red"
bar_color = rep("gray50", length(method_names))
names(bar_color) = method_names
bar_color["Raw"] = "gray80"
bar_color["DISC"] = "red"
### MAE
mae_eq0 = matrix(nrow = length(method_names), ncol = length(repeats), dimnames = list(method_names, repeats))
scale_factor = 1 / ds_mode
for(ii in method_names){
  for(jj in repeats){
    eq0 = sum(data_list[["Raw"]] > 0 & data_list[["Observed"]][[jj]] == 0)
    sae_eq0 = sum(sapply(compare_gene, function(x){
      expressed_mask = data_list[["Raw"]][x, ] > 0 & data_list[["Observed"]][[jj]][x, ] == 0
      return(sum(abs(data_list[["Raw"]][x, expressed_mask] - (data_list[[ii]][[jj]][x, expressed_mask] * scale_factor))))
    }))
    mae_eq0[ii, jj] = sae_eq0 / eq0
  }
  print(mae_eq0[ii, ])
}
pdf(paste0(output_dir, "/MAE.pdf"), height = 5, width = 4.5)
barplot_usage(rowMeans(mae_eq0), standard_error = apply(mae_eq0, 1, ste), main = "Zero entries", cex.main = 1.5, bar_color = bar_color, text_color = text_color, use_data_order = T, ylab = "MAE", cex.lab = 1.5, font.main = 1)
dev.off()
### CMD
CMD_output_dir = paste0(output_dir, "/CMD")
dir.create(CMD_output_dir, showWarnings = F, recursive = T)
vst_file = paste0(CMD_output_dir, "/vst_gene.tsv")
if(file.exists(vst_file)){
  hvg_info = read.table(vst_file)
  print("load vst_file")
}else{
  hvg_info = FindVariableFeatures_vst_by_genes(data_list[["Raw"]])
  hvg_info = hvg_info[order(hvg_info$variance.standardized, decreasing = T), ]
  write.table(hvg_info, paste0(CMD_output_dir, "/vst_gene.tsv"), sep = "\t", quote = F, row.names = T, col.names = T)
}
used_feature_genes = rownames(hvg_info)[1:300]
cor_all = list()
for(method in names(data_list)){
  cor_all[[method]] = matrix(nrow = length(used_feature_genes), ncol = length(used_feature_genes), dimnames = list(used_feature_genes, used_feature_genes))
  this_mat = delete_lt0.5(data_list[[method]])[used_feature_genes, ]
  no_cores <- detectCores() - 1
  cl <- makeCluster(no_cores)
  clusterExport(cl, varlist = c("this_mat", "method"))
  return_list = parLapply(cl, seq(nrow(this_mat) - 1), function(x){
    return_vector = rep(NA, nrow(this_mat) - x)
    ii_express = this_mat[x, ]
    ii_mask = ii_express > 0
    for(jj in (x + 1):nrow(this_mat)){
      jj_express = this_mat[jj, ]
      if(method %in% c("")){
        express_mask = rep(T, length(ii_mask))
      }else{
        express_mask = ii_mask | jj_express > 0
      }
      if(sum(express_mask) > 0){
        this_corr = cor(ii_express[express_mask], jj_express[express_mask], use = "pairwise.complete.obs")
        if(is.na(this_corr)){
          return_vector[jj - x] = 0
        }else{
          return_vector[jj - x] = this_corr
        }
      }else{
        return_vector[jj - x] = 0
      }
    }
    return(list("return_vector" = return_vector))
  })
  stopCluster(cl)
  cor_all[[method]][1, 1] = 1
  for(jj in 1:length(return_list)){
    cor_all[[method]][jj, (jj + 1): nrow(this_mat)] = return_list[[jj]][["return_vector"]]
    cor_all[[method]][(jj + 1): nrow(this_mat), jj] = return_list[[jj]][["return_vector"]]
    cor_all[[method]][(jj + 1), (jj + 1)] = 1
  }
  print(method)
}
saveRDS(cor_all, paste0(CMD_output_dir, "/cor_all.rds"))
cmd_result = c()
for(method in method_names){
  cmd_result = c(cmd_result, calc_cmd(cor_all[["Raw"]], cor_all[[method]]))
}
names(cmd_result) = method_names
print(cmd_result)
pdf(paste0(output_dir, "/CMD.pdf"), height = 5, width = 4.5)
barplot_usage(cmd_result, main = "", cex.main = 1.5, bar_color = bar_color, text_color = text_color, use_data_order = T, ylab = "CMD", cex.lab = 1.5, font.main = 1, ylim = c(-0.1, 1))
dev.off()
### Gene correlation
gene_correlation_mat = matrix(nrow = gene_number, ncol = length(method_names), dimnames = list(compare_gene, method_names))

for(method in method_names){
  for(ii in compare_gene){
  	raw_expression = data_list[["Raw"]][ii, ]
  	raw_expressed_mask = raw_expression != 0
  	raw_expressed_entries = raw_expression[raw_expressed_mask]
  	if(length(table(raw_expressed_entries)) > 1 & length(raw_expressed_entries) >= (0.1 * cell_number)){
    	gene_correlation_mat[ii, method] <- cor(raw_expressed_entries, data_list[[method]][ii, raw_expressed_mask], method = "pearson")
  	}
  }
  print(method)
}
print(colMeans(gene_correlation_mat, na.rm = T))
pdf(paste0(output_dir, "/CORR_GENE.pdf"), height = 5, width = 4.5)
barplot_usage(colMeans(gene_correlation_mat, na.rm = T), main = "", cex.main = 1.5, bar_color = bar_color, text_color = text_color, use_data_order = T, decreasing = T, ylab = "Gene correlation with reference", cex.lab = 1.5, font.main = 1, ylim = c(-0.1, 1))
dev.off()
### Cell correlation
cell_correlation_mat = matrix(nrow = cell_number, ncol = length(method_names), dimnames = list(c(), method_names))
for(method in method_names){
  for(ii in seq(cell_number)){
  	raw_expression = data_list[["Raw"]][, ii]
  	raw_expressed_mask = raw_expression != 0
  	raw_expressed_entries = raw_expression[raw_expressed_mask]
  	if(length(table(raw_expressed_entries)) > 1 & length(raw_expressed_entries) >= (0.1 * gene_number)){
    	cell_correlation_mat[ii, method] <- cor(raw_expressed_entries, data_list[[method]][raw_expressed_mask, ii], method = "pearson")
  	}
  }
  print(method)
}
print(colMeans(cell_correlation_mat, na.rm = T))
pdf(paste0(output_dir, "/CORR_CELL.pdf"), height = 5, width = 4.5)
barplot_usage(colMeans(cell_correlation_mat, na.rm = T), main = "", cex.main = 1.5, bar_color = bar_color, text_color = text_color, use_data_order = T, decreasing = T, ylab = "Cell correlation with reference", cex.lab = 1.5, font.main = 1, ylim = c(-0.1, 1))
dev.off()









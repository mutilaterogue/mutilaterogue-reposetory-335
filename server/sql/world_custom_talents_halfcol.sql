-- world DB: retail "pyramid" trees - col takes half steps (0, 0.5, 1, 1.5, ...): the nodes of the next row
-- stand between the nodes of the previous one. The existing whole numbers stay as they are.
ALTER TABLE `custom_talent_node` MODIFY COLUMN `col` DECIMAL(4,1) UNSIGNED NOT NULL;
